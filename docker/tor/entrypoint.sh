#!/bin/sh
set -e

if [ -z "$TOR_CONTROL_PASSWORD" ]; then
    echo "TOR_CONTROL_PASSWORD is not set" >&2
    exit 1
fi

# Runs as the tor user (USER in the Dockerfile); the data dir must already be
# owned by tor, Tor refuses to start otherwise
if [ ! -O /var/lib/tor ]; then
    echo "/var/lib/tor is not owned by $(id -un); fix the volume with:" >&2
    echo "  docker run --rm -u root -v <volume>:/var/lib/tor <image> chown -R tor:tor /var/lib/tor" >&2
    exit 1
fi
chmod 700 /var/lib/tor

HASHED_PASSWORD=$(tor --quiet --hash-password "$TOR_CONTROL_PASSWORD" | tail -n 1)
case "$HASHED_PASSWORD" in
    16:[0-9A-F]*) ;;
    *) echo "Failed to hash TOR_CONTROL_PASSWORD" >&2; exit 1 ;;
esac

# torrc lives in the data volume so the root filesystem can stay read-only
TORRC=/var/lib/tor/torrc
umask 077
cat > "$TORRC" <<EOF
DataDirectory /var/lib/tor
SocksPort 127.0.0.1:9050
ControlPort 127.0.0.1:9051
HashedControlPassword $HASHED_PASSWORD
Log notice stdout
EOF

exec tor -f "$TORRC"
