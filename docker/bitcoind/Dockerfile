# syntax=docker/dockerfile:1

# Self-built bitcoind for the Raspberry Pi, built from GPG-verified source.
# Native arm64 build (run on the ARM Mac):
#   ./fetch-keys.sh        # once / when MAINTAINER_KEYS change
#   docker buildx build --platform linux/arm64 --load -t 4324363/bitcoind:32.1 .
#   docker push 4324363/bitcoind:32.1
#
# The target triple is derived from --platform (TARGETARCH); override with
# --build-arg HOST=... only if you know what you are doing.
# Wallet enabled: add -DENABLE_WALLET=ON -DENABLE_SQLITE=ON and drop NO_WALLET=1.

# Pin by digest for reproducible builds, e.g.
#   docker buildx imagetools inspect debian:bookworm-slim
#   --build-arg BASE=debian:bookworm-slim@sha256:<digest>
ARG BASE=debian:bookworm-slim

FROM ${BASE} AS build

ARG BITCOIN_VERSION=32.1
ARG TARGETARCH
ARG HOST=

# Release maintainers whose signatures must verify SHA256SUMS. The public
# keys are read from ./keys (committed, see fetch-keys.sh), never from a
# keyserver at build time. Review the signer list for each new version:
# https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/
#   E777299F... = Michael Ford (fanquake), 15281230... = Ava Chow (achow101)
ARG MAINTAINER_KEYS="E777299FC265DD04793070EB944D35F9AC3DB76A 152812300785C96444D3334D17565732E08E5E41"
# Number of distinct pinned maintainers that must have signed SHA256SUMS.
ARG MIN_SIGS=2

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential pkg-config python3 cmake ca-certificates curl gnupg \
    && rm -rf /var/lib/apt/lists/*

# Resolve the GNU triplet from the build platform and make sure it is the
# native one (depends would otherwise look for a non-existent cross toolchain).
RUN set -eux; \
    host="${HOST}"; \
    if [ -z "$host" ]; then \
      case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
        arm64) host=aarch64-linux-gnu ;; \
        amd64) host=x86_64-linux-gnu ;; \
        *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
      esac; \
    fi; \
    [ "$(gcc -dumpmachine)" = "$host" ] \
      || { echo "HOST=$host does not match native $(gcc -dumpmachine)" >&2; exit 1; }; \
    echo "$host" > /host

WORKDIR /fetch
RUN set -eux; \
    base="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}"; \
    for f in "bitcoin-${BITCOIN_VERSION}.tar.gz" SHA256SUMS SHA256SUMS.asc; do \
      curl -fSL --proto '=https' --tlsv1.2 --retry 5 -o "$f" "$base/$f"; \
    done

COPY keys/ /keys/

# Import pinned keys from the repo; every pinned key must be present and
# not revoked.
RUN set -eux; \
    gpg --batch --import /keys/*.gpg; \
    for fp in ${MAINTAINER_KEYS}; do \
      pub="$(gpg --batch --with-colons --list-keys "$fp" | grep '^pub:')" \
        || { echo "ERROR: key $fp missing in keys/ (run fetch-keys.sh)" >&2; exit 1; }; \
      [ "$(echo "$pub" | cut -d: -f2)" != "r" ] \
        || { echo "ERROR: key $fp is revoked" >&2; exit 1; }; \
    done

# Plain `gpg --verify` exits non-zero because other builders' keys are not
# imported. Instead count VALIDSIG lines (the pinned primary fingerprint
# appears in the line whether the sig was made with the primary or a subkey)
# from distinct pinned maintainers and require at least MIN_SIGS.
RUN set -eux; \
    status="$(gpg --batch --status-fd 1 --verify SHA256SUMS.asc SHA256SUMS 2>/dev/null || true)"; \
    n=0; \
    for fp in ${MAINTAINER_KEYS}; do \
      if echo "$status" | grep '^\[GNUPG:\] VALIDSIG ' | grep -qw "$fp"; then \
        n=$((n + 1)); \
      fi; \
    done; \
    [ "$n" -ge "${MIN_SIGS}" ] \
      || { echo "ERROR: $n trusted signature(s) on SHA256SUMS, need ${MIN_SIGS}" >&2; exit 1; }; \
    grep " bitcoin-${BITCOIN_VERSION}.tar.gz\$" SHA256SUMS | sha256sum -c -

WORKDIR /src
RUN tar -xzf "/fetch/bitcoin-${BITCOIN_VERSION}.tar.gz" --strip-components=1 \
    && [ -f CMakeLists.txt ] \
    || { echo "ERROR: no CMakeLists.txt; only Bitcoin Core >= 29 is supported" >&2; exit 1; }

# depends: builds boost (headers, via CMake) and libevent as static libs;
# their source hashes are pinned in depends/packages/*.mk (signed tarball).
RUN make -j"$(nproc)" -C depends HOST="$(cat /host)" \
        NO_QT=1 NO_WALLET=1 NO_ZMQ=1 NO_UPNP=1 NO_NATPMP=1 NO_MULTIPROCESS=1

RUN set -eux; \
    host="$(cat /host)"; \
    cmake -B build \
        -DCMAKE_TOOLCHAIN_FILE="depends/${host}/toolchain.cmake" \
        -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_WALLET=OFF -DENABLE_ZMQ=OFF -DENABLE_IPC=OFF \
        -DBUILD_TESTS=OFF -DBUILD_BENCH=OFF -DBUILD_FUZZ_BINARY=OFF; \
    cmake --build build -j"$(nproc)" --target bitcoind bitcoin-cli; \
    mkdir -p /out/bin; \
    cp build/bin/bitcoind build/bin/bitcoin-cli /out/bin/

# Sanity/hardening checks (fail the build instead of shipping a weak binary):
# PIE, full RELRO, non-executable stack, stack protector, fully static
# boost/libevent.
RUN set -eux; \
    for b in /out/bin/bitcoind /out/bin/bitcoin-cli; do \
      readelf -h "$b" | grep -q 'Type:.*DYN'                     || { echo "$b: not PIE" >&2; exit 1; }; \
      readelf -lW "$b" | grep -q 'GNU_RELRO'                     || { echo "$b: no RELRO" >&2; exit 1; }; \
      readelf -dW "$b" | grep -Eq 'BIND_NOW|FLAGS.*NOW'          || { echo "$b: no BIND_NOW" >&2; exit 1; }; \
      readelf -lW "$b" | grep 'GNU_STACK' | grep -qv 'RWE'       || { echo "$b: exec stack" >&2; exit 1; }; \
      readelf -sW "$b" | grep -q '__stack_chk_fail'              || { echo "$b: no stack protector" >&2; exit 1; }; \
      if ldd "$b" | grep -Ei 'boost|libevent'; then echo "$b: unexpected dynamic libs" >&2; exit 1; fi; \
    done; \
    strip /out/bin/bitcoind /out/bin/bitcoin-cli; \
    /out/bin/bitcoind -version | head -n1 | grep -q "v${BITCOIN_VERSION}"

FROM ${BASE}

RUN set -eux; \
    addgroup --system --gid 1000 bitcoin; \
    adduser --system --uid 1000 --ingroup bitcoin --home /home/bitcoin \
        --shell /usr/sbin/nologin bitcoin; \
    install -d -o 1000 -g 1000 /home/bitcoin; \
    install -d -o 1000 -g 1000 -m 0750 /home/bitcoin/.bitcoin

COPY --from=build /out/bin/bitcoind /out/bin/bitcoin-cli /usr/local/bin/

USER bitcoin
WORKDIR /home/bitcoin
# Declared so a fresh named volume inherits the 1000:1000 ownership above.
# Always mount a named volume here; otherwise Docker silently creates an
# anonymous one and the chain data is lost on `docker compose down`.
VOLUME /home/bitcoin/.bitcoin
EXPOSE 8332 8333
# bitcoind flushes its UTXO cache on SIGTERM; give it time in compose with
# stop_grace_period (the 10s default is far too short).
STOPSIGNAL SIGTERM
ENTRYPOINT ["bitcoind"]
CMD ["-printtoconsole"]
