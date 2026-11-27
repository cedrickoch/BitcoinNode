#!/bin/sh
# Report how old the running images are, and optionally perform the deliberate
# refresh. Floating tags never refreshed themselves, which is why this exists.
#
# Without --pull it only reports. With --pull it runs `docker compose pull` and
# then tells you which images actually changed, so a refresh is a decision and
# not a surprise.
#
# Exit codes: 0 clean, 1 unpinned reference or pull failure, 2 usage problem.
#
# Usage: scripts/refresh-images.sh [--pull]

set -eu

cd "$(dirname "$0")/.."

DO_PULL=0
case "${1:-}" in
    "") ;;
    --pull) DO_PULL=1 ;;
    -h|--help) echo "usage: $0 [--pull]" >&2; exit 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
esac

FILES=$(ls docker-compose*.yml 2>/dev/null || true)
[ -n "$FILES" ] || { echo "no compose files found" >&2; exit 2; }

# Every external reference, with file and line.
refs=$(grep -HnE '^[[:space:]]+image:[[:space:]]*' $FILES | sed -E 's/^([^:]+):([0-9]+):[[:space:]]+image:[[:space:]]*//' \
       | sed -E 's/[[:space:]]*#.*$//' | sort -u)

[ -n "$refs" ] || { echo "no image references found" >&2; exit 2; }

problem=0
printf '%-12s %s\n' "AGE" "REFERENCE"
printf '%s\n' "---------------------------------------------------------------"

for ref in $refs; do
    # a version tag is anything after the last colon that is not "latest"
    tag=$(printf '%s' "$ref" | sed -E 's#^.*/##; s#^[^:]*:?##')
    if [ -z "$tag" ] || [ "$tag" = "latest" ]; then
        printf '%-12s %s\n' "UNPINNED" "$ref"
        problem=1
    fi

    created=$(docker image inspect -f '{{.Created}}' "$ref" 2>/dev/null | cut -c1-10 || true)
    if [ -z "$created" ]; then
        created="not-pulled"
    fi
    printf '%-12s %s\n' "$created" "$ref"
done

if [ "$DO_PULL" -eq 0 ]; then
    echo
    echo "Report only. Run with --pull to refresh, then: docker compose up -d"
    echo "Node mid-sync? A refresh is safe but re-downloads. See docs/trust.md."
    [ "$problem" -eq 0 ] || { echo "unpinned reference(s) above" >&2; exit 1; }
    exit 0
fi

[ "$problem" -eq 0 ] || echo "note: unpinned reference(s) above will follow whatever the tag now points at"

echo
echo "Pulling..."
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    COMPOSE="docker compose"
else
    COMPOSE="docker-compose"
fi

before=$(docker image ls --format '{{.Repository}}:{{.Tag}} {{.ID}}' 2>/dev/null | sort)
# shellcheck disable=SC2086
if ! $COMPOSE $(printf -- '-f %s ' $FILES) pull 2>&1 | tail -n 40; then
    echo "pull failed" >&2
    exit 1
fi
after=$(docker image ls --format '{{.Repository}}:{{.Tag}} {{.ID}}' 2>/dev/null | sort)

changed=$(printf '%s\n%s\n' "$before" "$after" | sort | uniq -u | awk '{print $1}' | sort -u)
if [ -z "$changed" ]; then
    echo "no image changed"
else
    echo "changed:"
    printf '  %s\n' $changed
    echo
    echo "Apply with: docker compose up -d"
    echo "Then check: scripts/security-status.sh"
fi

[ "$problem" -eq 0 ] || exit 1
exit 0
