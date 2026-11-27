#!/bin/sh
# Report the live hardening posture of every running service and flag anything
# that departs from docs/hardening-baseline.md.
#
# Deviations are data: a matching row in the baseline's "Justified deviations"
# table turns a finding into `deviated`. An *undocumented* deviation is `DRIFT`.
# A row with no live deviation is `stale-deviation`, so the table cannot rot.
#
# Exit codes: 0 clean, 1 drift found, 2 environment problem.
#
# Usage: scripts/audit-hardening.sh [--json] [--strict]

set -eu

cd "$(dirname "$0")/.."

BASELINE="docs/hardening-baseline.md"
JSON=0
STRICT=0

for arg in "$@"; do
    case "$arg" in
        --json) JSON=1 ;;
        --strict) STRICT=1 ;;
        -h|--help) echo "usage: $0 [--json] [--strict]" >&2; exit 2 ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

[ -f "$BASELINE" ] || { echo "missing $BASELINE" >&2; exit 2; }
command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 2; }
docker info >/dev/null 2>&1 || { echo "cannot reach the docker daemon" >&2; exit 2; }

ids=$(docker compose ps -q 2>/dev/null || true)
[ -n "$ids" ] || { echo "no running containers for this project" >&2; exit 2; }

# service | key | reason   (rows of the baseline's deviation table)
deviations=$(awk '
    /^\| *service *\| *key *\|/ { intable = 1; next }
    intable {
        if ($0 !~ /^\|/) { exit }
        if ($0 ~ /^\| *-/) { next }
        n = split($0, c, "|")
        if (n < 4) { next }
        s = c[2]; k = c[3]
        gsub(/^[ \t]+|[ \t]+$/, "", s)
        gsub(/^[ \t]+|[ \t]+$/, "", k)
        # "`cap_add` (CHOWN, ...)" -> cap_add
        gsub(/ \(.*\)$/, "", k)
        gsub(/`/, "", s); gsub(/`/, "", k)
        if (s != "" && k != "") print s "|" k
    }
' "$BASELINE")

seen=""
drift=0
deviated=0
stale=0
total=0

json_open=0

emit() {
    # emit <service> <key> <live-value> <verdict>
    if [ "$JSON" -eq 1 ]; then
        [ "$json_open" -eq 1 ] && printf ',\n'
        json_open=1
        printf '  {"service":"%s","key":"%s","value":"%s","verdict":"%s"}' "$1" "$2" "$3" "$4"
    else
        printf '%-8s %-18s %-16s %s\n' "$4" "$1" "$2" "$3"
    fi
}

[ "$JSON" -eq 1 ] && printf '[\n'

for id in $ids; do
    svc=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' "$id")
    total=$((total + 1))

    cap_drop=$(docker inspect -f '{{join .HostConfig.CapDrop ","}}' "$id")
    cap_add=$(docker inspect -f '{{join .HostConfig.CapAdd ","}}' "$id")
    nnp=$(docker inspect -f '{{join .HostConfig.SecurityOpt ","}}' "$id")
    pids=$(docker inspect -f '{{.HostConfig.PidsLimit}}' "$id")
    ronly=$(docker inspect -f '{{.HostConfig.ReadonlyRootfs}}' "$id")
    usr=$(docker inspect -f '{{.Config.User}}' "$id")
    hlth=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$id")

    check() {
        # check <key> <ok?> <live-value>
        if [ "$2" = 1 ]; then
            emit "$svc" "$1" "$3" ok
            return
        fi
        if printf '%s\n' "$deviations" | grep -qxF "$svc|$1"; then
            emit "$svc" "$1" "$3" deviated
            deviated=$((deviated + 1))
            seen="$seen $svc|$1"
        else
            emit "$svc" "$1" "$3" DRIFT
            drift=$((drift + 1))
        fi
    }

    [ "$cap_drop" = "ALL" ] && check cap_drop 1 "$cap_drop" || check cap_drop 0 "${cap_drop:-none}"

    if [ -z "$cap_add" ]; then
        check cap_add 1 none
    else
        check cap_add 0 "$cap_add"
    fi

    case "$nnp" in
        *no-new-privileges:true*) check security_opt 1 present ;;
        *) check security_opt 0 "${nnp:-none}" ;;
    esac

    if [ -n "$pids" ] && [ "$pids" != "0" ]; then
        check pids_limit 1 "$pids"
    else
        check pids_limit 0 unset
    fi

    [ "$ronly" = "true" ] && check read_only 1 true || check read_only 0 false

    case "$usr" in
        ""|root|0|0:*|*:0|"root:"*) check user 0 "${usr:-root}" ;;
        *) check user 1 "$usr" ;;
    esac

    [ "$hlth" != "none" ] && check healthcheck 1 "$hlth" || check healthcheck 0 none
done

# a documented deviation with no live deviation is out of date
if [ -n "$deviations" ]; then
    for row in $deviations; do
        case " $seen " in
            *" $row "*) ;;
            *)  key=${row#*|}
                svc=${row%%|*}
                # only meaningful for services that are actually running
                if docker compose ps --services 2>/dev/null | grep -qxF "$svc"; then
                    emit "$svc" "$key" "-" stale-deviation
                    stale=$((stale + 1))
                fi ;;
        esac
    done
fi

if [ "$JSON" -eq 1 ]; then
    printf '\n]\n'
    printf '{"services":%s,"drift":%s,"deviated":%s,"stale":%s}\n' "$total" "$drift" "$deviated" "$stale"
else
    echo
    printf '%s service(s); %s drift, %s deviated, %s stale deviation row(s)\n' "$total" "$drift" "$deviated" "$stale"
    [ "$drift" -eq 0 ] || echo "See docs/hardening-baseline.md."
fi

[ "$drift" -eq 0 ] || exit 1
[ "$stale" -eq 0 ] || exit 1
if [ "$STRICT" -eq 1 ] && [ "$deviated" -gt 0 ]; then exit 1; fi
exit 0
