#!/bin/sh
set -e

if [ -z "$TOR_CONTROL_PASSWORD" ]; then
    echo "TOR_CONTROL_PASSWORD is not set" >&2
    exit 1
fi

# Tor refuses to start unless its data directory is private to the tor user
mkdir -p /var/lib/tor
chown -R tor /var/lib/tor
chmod 700 /var/lib/tor

HASHED_PASSWORD=$(tor --quiet --hash-password "$TOR_CONTROL_PASSWORD" | tail -n 1)

cat > /etc/tor/torrc <<EOF
User tor
DataDirectory /var/lib/tor
SocksPort 127.0.0.1:9050
ControlPort 127.0.0.1:9051
HashedControlPassword $HASHED_PASSWORD
Log notice stdout
EOF

exec tor -f /etc/tor/torrc
