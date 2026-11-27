#!/bin/sh
# Check that each compose overlay keeps the hardening baseline of docker-compose.yml.
#
# Overlays are standalone (see docs/hardening-baseline.md), so they inherit
# nothing and must repeat the baseline themselves. This catches the drift that
# makes a non-default mode weaker than the default one.
#
# Exit codes: 0 clean, 1 drift found, 2 usage or environment problem.
#
# Usage: scripts/check-overlay-parity.sh [--verbose] [overlay-file ...]

set -eu

cd "$(dirname "$0")/.."

BASE="docker-compose.yml"
VERBOSE=0

# Overlays that are meant to be stacked on the base file and only need to add
# what they change, so they are excluded from the presence check.
STACKED="docker-compose.private.yml"

usage() {
    echo "usage: $0 [--verbose] [overlay-file ...]" >&2
    exit 2
}

FILES=""
for arg in "$@"; do
    case "$arg" in
        --verbose) VERBOSE=1 ;;
        -h|--help) usage ;;
        -*) echo "unknown option: $arg" >&2; usage ;;
        *) FILES="$FILES $arg" ;;
    esac
done

[ -f "$BASE" ] || { echo "missing $BASE" >&2; exit 2; }

if [ -z "$FILES" ]; then
    for f in docker-compose-*.yml; do
        [ -f "$f" ] || continue
        [ "$f" = "$STACKED" ] && continue
        FILES="$FILES $f"
    done
fi

# Keys compared for exact equality between the base service and the overlay service.
# `healthcheck` and `logging` are cross-cutting: every standalone overlay must
# repeat them, so a mode cannot silently lose a health signal or a log bound.
CHECKED_KEYS="cap_drop cap_add security_opt pids_limit read_only user image healthcheck logging"

# Print "key|value" for the given service, joining YAML flow and block sequences
# so that `cap_drop: [ALL]` and a multi-line `- ALL` list compare equal.
service_keys() {
    awk -v want="$2" '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        function flush() {
            if (key != "") { printf "%s|%s\n", key, val }
            key = ""; val = ""
        }
        /^[ \t]*#/ { next }
        /^[ \t]*$/ { flush(); next }
        # a top-level key (column 0) outside `services:` ends the services block
        /^[A-Za-z]/ {
            flush()
            if ($0 ~ /^services:[ \t]*$/) { in_services = 1; in_svc = 0; next }
            in_services = 0; in_svc = 0
            next
        }
        !in_services { next }
        # service header: exactly 4 spaces, name, colon, nothing else
        /^    [A-Za-z0-9_.-]+:[ \t]*$/ {
            flush()
            svc = $0; sub(/^    /, "", svc); sub(/:.*/, "", svc)
            in_svc = (svc == want)
            next
        }
        !in_svc { next }
        {
            line = $0
            if (match(line, /^[ \t]*[A-Za-z0-9_.-]+:[ \t]*/)) {
                head = substr(line, 1, RLENGTH)
                rest = substr(line, RLENGTH + 1)
                flush()
                key = trim(head); sub(/:$/, "", key)
                if (key == "") { key = "" ; next }
                if (match(rest, /^\[.*\]/)) {
                    v = substr(rest, 2, RLENGTH - 2)
                    gsub(/[ \t]/, "", v)
                    sub(/,$/, "", v)
                    val = v
                    next
                }
                rest = trim(rest)
                sub(/[ \t]+#.*$/, "", rest)
                val = rest
                # block sequence?
                if (val == "") { blockkey = key; next }
                next
            }
            # indented item of a block sequence
            if (blockkey != "" && match(line, /^[ \t]*-[ \t]+/)) {
                item = line; sub(/^[ \t]*-[ \t]+/, "", item)
                item = trim(item); sub(/[ \t]+#.*$/, "", item)
                val = (val == "") ? item : val "," item
                next
            }
            if (match(line, /^[ \t]*-[ \t]+/)) {
                item = line; sub(/^[ \t]*-[ \t]+/, "", item)
                key = blockkey
                blockkey = ""
                val = trim(item); sub(/[ \t]+#.*$/, "", val)
                next
            }
        }
        function verbose_keys(k) { return 0 }
        END { flush() }
    ' "$1"
}

normalise() {
    # strip quotes and spaces so "no-new-privileges:true" == no-new-privileges:true
    sed -e 's/"//g' -e "s/'//g" -e 's/[ \t]//g' -e 's/,$//' | sort
}

value_of() {
    # value_of <keys-blob> <key>
    printf '%s\n' "$1" | awk -F'|' -v k="$2" '$1 == k { sub(/^[^|]*\|/, ""); print }'
}

# Keys a service explicitly opts out of, via `# parity:allow <key>` comments.
allowed_keys() {
    awk -v want="$2" '
        /^[A-Za-z]/ { if ($0 ~ /^services:[ \t]*$/) { ins = 1; next } ins = 0; next }
        !ins { next }
        /^    [A-Za-z0-9_.-]+:[ \t]*$/ {
            svc = $0; sub(/^    /, "", svc); sub(/:.*/, "", svc); in_svc = (svc == want); next
        }
        !in_svc { next }
        /parity:allow/ {
            line = $0; sub(/.*parity:allow[ \t]*/, "", line); sub(/[ \t]*#.*$/, "", line)
            n = split(line, parts, /[ ,]+/)
            for (i = 1; i <= n; i++) if (parts[i] != "") print parts[i]
        }
    ' "$1"
}

drift=0
checked=0
command -v awk >/dev/null 2>&1 || { echo "awk is required" >&2; exit 2; }

for file in $FILES; do
    [ -f "$file" ] || { echo "missing $file" >&2; exit 2; }

    # A stacked overlay adds to the base file, so only its own keys count.
    lenient=0
    case " $STACKED " in *" $file "*) lenient=1 ;; esac

    # every service the overlay defines that also exists in the base
    services=$(awk '
        /^[ \t]*#/ { next }
        /^[A-Za-z]/ { if ($0 ~ /^services:[ \t]*$/) { ins = 1; next } ins = 0; next }
        !ins { next }
        /^    [A-Za-z0-9_.-]+:[ \t]*$/ { s = $0; sub(/^    /, "", s); sub(/:.*/, "", s); print s }
    ' "$file")

    for svc in $services; do
        base_blob=$(service_keys "$BASE" "$svc")
        if [ -z "$base_blob" ]; then
            if [ "$VERBOSE" = 1 ]; then
                echo "skip  $file $svc (not in base)"
            fi
            continue
        fi
        ovl_blob=$(service_keys "$file" "$svc")
        checked=$((checked + 1))
        # space-separated so the case patterns below can match at either end
        allowed=$(allowed_keys "$file" "$svc" | tr '\n' ' ')

        for key in $CHECKED_KEYS; do
            case " $allowed " in
                *" $key "*)
                    [ "$VERBOSE" = 1 ] && printf 'allow %s %s %s (documented deviation)\n' "$file" "$svc" "$key"
                    continue ;;
            esac
            base_val=$(normalise <<EOF
$(value_of "$base_blob" "$key")
EOF
)
            ovl_val=$(normalise <<EOF
$(value_of "$ovl_blob" "$key")
EOF
)
            if [ "$base_val" != "$ovl_val" ]; then
                if [ "$lenient" = 1 ] && [ -z "$ovl_val" ]; then
                    [ "$VERBOSE" = 1 ] && printf 'ok    %s %s %s=<inherited>\n' "$file" "$svc" "$key"
                    continue
                fi
                drift=$((drift + 1))
                printf 'DRIFT %s %s %s: base=%s overlay=%s\n' \
                    "$file" "$svc" "$key" \
                    "${base_val:-<unset>}" "${ovl_val:-<unset>}"
            elif [ "$VERBOSE" = 1 ]; then
                printf 'ok    %s %s %s=%s\n' "$file" "$svc" "$key" "${ovl_val:-<unset>}"
            fi
        done
    done
done

if [ "$checked" -eq 0 ]; then
    echo "no comparable services found (checked no overlay against $BASE)" >&2
    exit 2
fi

if [ "$drift" -gt 0 ]; then
    printf '\n%s drift(s) across %s service(s) in %s\n' "$drift" "$checked" "$BASE"
    echo "See docs/hardening-baseline.md."
    exit 1
fi

printf 'OK: %s service(s) match the hardening baseline in %s\n' "$checked" "$BASE"
exit 0
