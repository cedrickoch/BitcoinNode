#!/bin/sh
# Show whether each service is actually doing its job: one line per service, plus
# an overall verdict. Reads the engine's health state; never changes anything.
#
# `healthy` needs a declared healthcheck. A running service with none is
# `no-healthcheck` — acceptable only for the one-shot import mode.
#
# Exit codes: 0 all healthy, 1 anything unhealthy/starting/no-healthcheck, 2 problem.
#
# Usage: scripts/security-status.sh [--json]

set -eu

cd "$(dirname "$0")/.."

JSON=0
case "${1:-}" in
    "") ;;
    --json) JSON=1 ;;
    -h|--help) echo "usage: $0 [--json]" >&2; exit 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
esac

command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 2; }
docker info >/dev/null 2>&1 || { echo "cannot reach the docker daemon" >&2; exit 2; }

ids=$(docker compose ps -q 2>/dev/null || true)
[ -n "$ids" ] || { echo "no containers for this project (start the stack first)" >&2; exit 2; }

overall=healthy
first=1
[ "$JSON" -eq 1 ] && printf '[\n'

for id in $ids; do
    svc=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' "$id")
    state=$(docker inspect -f '{{.State.Status}}' "$id")
    health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$id")
    detail="-"

    if [ "$state" != "running" ]; then
        verdict="unhealthy"
        detail="state=$state"
    else
        case "$health" in
            healthy) verdict="healthy" ;;
            starting) verdict="starting" ;;
            unhealthy)
                verdict="unhealthy"
                # last probe output, first line only, keeps the report useful
                detail=$(docker inspect -f '{{if .State.Health}}{{with index .State.Health.Log 0}}{{.Output}}{{end}}{{end}}' "$id" 2>/dev/null | head -n 1 | cut -c1-60)
                [ -n "$detail" ] || detail="probe failing" ;;
            none) verdict="no-healthcheck" ;;
            *) verdict="unknown"; detail="$health" ;;
        esac
    fi

    # dependents of a down node are not meaningfully probed: say so
    if [ "$svc" != "bitcoin" ] && [ "$verdict" = "unhealthy" ]; then
        bstate=$(docker inspect -f '{{.State.Status}}' \
            "$(docker compose ps -q bitcoin 2>/dev/null | head -n 1)" 2>/dev/null || echo "")
        [ "$bstate" = "running" ] || detail="$detail (node down)"
    fi

    case "$verdict" in
        healthy|no-healthcheck) ;;
        *) overall=unhealthy ;;
    esac

    if [ "$JSON" -eq 1 ]; then
        [ "$first" -eq 1 ] || printf ',\n'
        first=0
        printf '  {"service":"%s","state":"%s","verdict":"%s","detail":"%s"}' \
            "$svc" "$state" "$verdict" "${detail//\"/}"
    else
        printf '%-14s %-16s %s\n' "$verdict" "$svc" "$detail"
    fi
done

if [ "$JSON" -eq 1 ]; then
    printf '\n]\n'
    printf '{"overall":"%s"}\n' "$overall"
else
    echo
    echo "OVERALL: $overall"
    if [ "$overall" != "healthy" ]; then
        echo "First step per service is in the README's troubleshooting notes."
    fi
fi

[ "$overall" = "healthy" ] || exit 1
exit 0
