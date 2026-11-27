#!/bin/sh
# Fill every blank credential in .env with a random value.
#
# Design: .env is the only place secrets live (gitignored). Compose uses
# ${VAR:?message} so a blank value fails the start loudly instead of falling
# back to a committed default. This script removes the resulting first-run
# deadlock: it creates .env if missing, then fills blanks. It NEVER overwrites a
# value you already set, and it never prints a value — only the name it filled.
#
# Exit codes: 0 done, 1 environment problem, 2 usage problem.
#
# Usage: scripts/generate-secrets.sh [--force-missing]

set -eu

cd "$(dirname "$0")/.."

ENV_FILE=".env"
TEMPLATE=".env.example"

# Every secret compose expects. Keep in sync with .env.example.
SECRETS="TOR_CONTROL_PASSWORD MYSQL_PASSWORD MYSQL_ROOT_PASSWORD"

usage() {
    echo "usage: $0 [--force-missing]" >&2
    exit 2
}

case "${1:-}" in
    "") ;;
    --force-missing) ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
esac

[ -f "$TEMPLATE" ] || { echo "missing $TEMPLATE" >&2; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "openssl is required" >&2; exit 1; }

if [ ! -f "$ENV_FILE" ]; then
    cp "$TEMPLATE" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    echo "created $ENV_FILE from $TEMPLATE"
fi

[ -w "$ENV_FILE" ] || { echo "$ENV_FILE is not writable" >&2; exit 1; }

generated=0
for name in $SECRETS; do
    current=$(awk -v k="$name" '
        /^[ \t]*#/ { next }
        $0 ~ "^[ \t]*"k"=" {
            sub(/^[^=]*=/, "")
            gsub(/^[ \t]+|[ \t]+$/, "")
            print
            exit
        }
    ' "$ENV_FILE")

    if [ -n "$current" ]; then
        continue
    fi

    value=$(openssl rand -hex 24)

    if grep -qE "^[ \t]*$name=" "$ENV_FILE"; then
        # replace the empty assignment in place, keeping the file's ordering
        awk -v k="$name" -v v="$value" '
            !done && $0 ~ "^[ \t]*"k"=" { print k"="v; done = 1; next }
            { print }
        ' "$ENV_FILE" > "$ENV_FILE.tmp"
        # mv replaces the inode, so re-assert the private mode
        chmod 600 "$ENV_FILE.tmp"
        mv "$ENV_FILE.tmp" "$ENV_FILE"
    else
        printf '%s=%s\n' "$name" "$value" >> "$ENV_FILE"
    fi

    echo "WARN: $name generated — review it in $ENV_FILE"
    generated=$((generated + 1))
done

if [ "$generated" -eq 0 ]; then
    echo "OK: no blank credentials in $ENV_FILE"
else
    echo "OK: generated $generated credential(s); rotate database passwords with scripts/rotate-db-password.sh"
fi
