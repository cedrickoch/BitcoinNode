#!/bin/sh
# Download the pinned Bitcoin Core maintainer keys into ./keys and verify
# that each file contains exactly the expected primary fingerprint.
# Commit the resulting keys/*.gpg; the Docker build never hits a keyserver.
set -eu

cd "$(dirname "$0")"

# name:fingerprint  (must match MAINTAINER_KEYS in the Dockerfile)
KEYS="
fanquake:E777299FC265DD04793070EB944D35F9AC3DB76A
achow101:152812300785C96444D3334D17565732E08E5E41
"
SRC="https://raw.githubusercontent.com/bitcoin-core/guix.sigs/main/builder-keys"

mkdir -p keys
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for entry in $KEYS; do
    name="${entry%%:*}"
    fp="${entry#*:}"
    curl -fsSL --proto '=https' --tlsv1.2 -o "$tmp/$name.gpg" "$SRC/$name.gpg"
    got="$(gpg --batch --with-colons --show-keys "$tmp/$name.gpg" \
           | awk -F: '/^pub:/{p=1; next} p && /^fpr:/{print $10; p=0}')"
    if [ "$got" != "$fp" ]; then
        echo "ERROR: $name.gpg has fingerprint(s) '$got', expected $fp" >&2
        exit 1
    fi
    mv "$tmp/$name.gpg" "keys/$name.gpg"
    echo "ok  $name  $fp"
done
