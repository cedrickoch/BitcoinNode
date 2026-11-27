#!/bin/sh
# Rotate a database credential in the live database AND in .env, so the two can
# never drift apart. Chain data is never touched.
#
# Order is forced by MariaDB: the grant is the authority, so it changes first;
# the consumers restart afterwards so they pick the new value up.
#
# MariaDB only honours MYSQL_PASSWORD when the volume is first initialised, which
# is why changing .env alone is not enough for an existing deployment.
#
# Exit codes: 0 rotated, 1 environment/database problem, 2 usage problem.
#
# Usage: scripts/rotate-db-password.sh app|root [--value <new-password>]

set -eu

cd "$(dirname "$0")/.."

ENV_FILE=".env"
TARGET=""
VALUE=""

usage() {
    cat >&2 <<'EOF'
usage: scripts/rotate-db-password.sh app|root [--value <new-password>]

  app    rotate MYSQL_PASSWORD (the explorer's database user)
  root   rotate MYSQL_ROOT_PASSWORD (database superuser)
EOF
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        app|root) TARGET="$1" ;;
        --value)
            [ $# -ge 2 ] || { echo "--value needs an argument" >&2; usage; }
            VALUE="$2"; shift ;;
        -h|--help) usage ;;
        *) echo "unknown argument: $1" >&2; usage ;;
    esac
    shift
done

[ -n "$TARGET" ] || usage
[ -f "$ENV_FILE" ] || { echo "missing $ENV_FILE" >&2; exit 1; }

# Map the target onto the compose variable, the SQL user and the consumer services.
case "$TARGET" in
    app)
        VAR="MYSQL_PASSWORD"
        DB_USER="mempool"
        CONSUMERS="api web" ;;
    root)
        VAR="MYSQL_ROOT_PASSWORD"
        DB_USER="root"
        CONSUMERS="" ;;
esac

# The database must be running: the grant is changed in place.
if ! docker compose ps --status running --services 2>/dev/null | grep -qx db; then
    echo "db is not running; start the stack first" >&2
    exit 1
fi

CURRENT=$(awk -v k="$VAR" '
    /^[ \t]*#/ { next }
    $0 ~ "^[ \t]*"k"=" { sub(/^[^=]*=/, ""); gsub(/[ \t]/,""); print; exit }
' "$ENV_FILE")
[ -n "$CURRENT" ] || { echo "$VAR is empty in $ENV_FILE; run scripts/generate-secrets.sh" >&2; exit 1; }

if [ -z "$VALUE" ]; then
    VALUE=$(openssl rand -hex 24)
fi

# Refuse a value MariaDB or the env file would mangle.
case "$VALUE" in
    *[!A-Za-z0-9._-]*) echo "value must be alphanumeric plus . _ - only" >&2; exit 2 ;;
esac

# 1. change the grant. The container's mysql client runs as root over the unix
# socket; MYSQL_PWD supplies the current password as a fallback for images that
# do not grant socket auth.
if [ "$TARGET" = "root" ]; then
    # rotate every root host that exists, so both socket and TCP logins follow
    ALTER=""
    for host in '%' localhost 127.0.0.1; do
        ALTER="$ALTER ALTER USER IF EXISTS 'root'@'${host}' IDENTIFIED BY '${VALUE}';"
    done
else
    ALTER="ALTER USER '${DB_USER}'@'%' IDENTIFIED BY '${VALUE}';"
fi

if ! docker compose exec -T -e MYSQL_PWD="$CURRENT" db \
        mysql --protocol=socket -uroot -e "$ALTER" 2>/dev/null; then
    echo "ALTER USER failed; current $VAR did not authenticate" >&2
    exit 1
fi

# 2. record it in .env, preserving the existing file layout
awk -v k="$VAR" -v v="$VALUE" '
    !done && $0 ~ "^[ \t]*"k"=" { print k"="v; done = 1; next }
    { print }
' "$ENV_FILE" > "$ENV_FILE.tmp"
chmod 600 "$ENV_FILE.tmp"
mv "$ENV_FILE.tmp" "$ENV_FILE"

# 3. restart the consumers so they reconnect with the new value
if [ -n "$CONSUMERS" ]; then
    # shellcheck disable=SC2086
    docker compose up -d --no-deps $CONSUMERS >/dev/null
    echo "rotated $VAR and restarted: $CONSUMERS"
else
    echo "rotated $VAR; restart the stack to apply it"
fi
