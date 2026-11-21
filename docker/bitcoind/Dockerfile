# syntax=docker/dockerfile:1

# Self-built bitcoind for the Raspberry Pi, built from GPG-verified source.
# Native arm64 build (run on the ARM Mac):
#   docker build -t 4324363/bitcoind:32.1 .
#   docker push 4324363/bitcoind:32.1
#
# Other arch: --build-arg HOST=x86_64-linux-gnu
# Wallet enabled: add -DENABLE_WALLET=ON -DENABLE_SQLITE=ON and drop NO_WALLET=1
# (depends then also builds sqlite; wallet code needs the sqlite dev package).

ARG BASE=debian:bookworm-slim

FROM ${BASE} AS build

ARG BITCOIN_VERSION=32.1
# GNU triplet for the target machine; aarch64-linux-gnu = native on ARM
# (Apple Silicon Docker / Raspberry Pi). It must match the build triple,
# otherwise depends looks for a cross toolchain (arm64-linux-gnu-g++ does
# not exist in Debian).
ARG HOST=aarch64-linux-gnu

# Release maintainers whose signatures must verify SHA256SUMS.
# Review the signer list on the release page for each new version:
# https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/
ARG MAINTAINER_KEYS="E777299FC265DD04793070EB944D35F9AC3DB76A 152812300785C96444D3334D17565732A0850599"

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential libtool autotools-dev automake pkg-config bsdmainutils \
        python3 cmake ca-certificates curl wget gnupg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /fetch
RUN set -eux; \
    base="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}"; \
    curl -fSL --retry 5 -o "bitcoin-${BITCOIN_VERSION}.tar.gz" "$base/bitcoin-${BITCOIN_VERSION}.tar.gz"; \
    curl -fSL --retry 5 -o SHA256SUMS "$base/SHA256SUMS"; \
    curl -fSL --retry 5 -o SHA256SUMS.asc "$base/SHA256SUMS.asc"

# Import trusted maintainer keys, with a fallback keyserver per key.
# Individual import failures are tolerated; requiring at least one imported
# key here, plus the signature check below, keeps verification fail-closed.
RUN set -eux; \
    for fp in ${MAINTAINER_KEYS}; do \
      gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys "$fp" \
        || gpg --keyserver hkps://keys.openpgp.org --recv-keys "$fp" \
        || true; \
    done; \
    [ "$(gpg --list-keys --with-colons | grep -c '^pub')" -ge 1 ]

# Plain `gpg --verify` would exit 2: other builders also signed SHA256SUMS and
# their keys are not imported ("Can't check signature: No public key").
# Instead require at least one VALIDSIG whose primary fingerprint is trusted.
RUN set -eux; \
    ok=0; \
    for fp in ${MAINTAINER_KEYS}; do \
      if gpg --status-fd 1 --verify SHA256SUMS.asc SHA256SUMS 2>/dev/null \
           | grep "^\[GNUPG:\] VALIDSIG" | grep -qw "$fp"; then \
        ok=1; \
      fi; \
    done; \
    [ "$ok" = "1" ] || { echo "ERROR: no trusted signature on SHA256SUMS" >&2; exit 1; }; \
    grep " bitcoin-${BITCOIN_VERSION}.tar.gz\$" SHA256SUMS | sha256sum -c -

WORKDIR /src
RUN tar -xzf "/fetch/bitcoin-${BITCOIN_VERSION}.tar.gz" --strip-components=1

# depends system: builds boost (via CMake, hence the cmake install above)
# and libevent. NO_* skips packages the configure flags don't need (qt/capnp
# would also require cmake; capnp is only for --enable-multiprocess, which we
# don't use). HOST must match the build triple (native build).
RUN make -j"$(nproc)" -C depends HOST="${HOST}" \
        NO_QT=1 NO_WALLET=1 NO_ZMQ=1 NO_UPNP=1 NO_NATPMP=1 NO_MULTIPROCESS=1

# Build. Bitcoin Core >= 29 uses CMake only (no autotools `configure` in the
# tarball); <= 28 had autotools and no CMakeLists.txt. Detect which tree we
# have so a version bump cannot break this step silently.
# The depends toolchain file supplies compilers and the static boost/libevent.
RUN set -eux; \
    mkdir -p /out/bin /out/lib; \
    if [ -f CMakeLists.txt ]; then \
        cmake -B build \
            -DCMAKE_TOOLCHAIN_FILE="depends/${HOST}/toolchain.cmake" \
            -DCMAKE_BUILD_TYPE=Release \
            -DENABLE_WALLET=OFF -DENABLE_ZMQ=OFF -DENABLE_IPC=OFF \
            -DBUILD_TESTS=OFF -DBUILD_BENCH=OFF -DBUILD_FUZZ_BINARY=OFF; \
        cmake --build build -j"$(nproc)" --target bitcoind bitcoin-cli; \
        cp build/bin/bitcoind build/bin/bitcoin-cli /out/bin/; \
    else \
        ./configure --prefix="/src/depends/${HOST}" \
            --disable-wallet --disable-gui --disable-zmq --disable-tests \
            --disable-bench --disable-man --with-libs=no; \
        make -j"$(nproc)"; \
        cp src/bitcoind src/bitcoin-cli /out/bin/; \
    fi; \
    strip /out/bin/bitcoind /out/bin/bitcoin-cli; \
    ldd /out/bin/bitcoind | awk '/boost|libevent/ {print $$3}' \
        | xargs -r -I{} cp -L {} /out/lib/

FROM ${BASE}

RUN set -eux; \
    addgroup --system --gid 1000 bitcoin; \
    adduser --system --uid 1000 --ingroup bitcoin --home /home/bitcoin --shell /bin/sh bitcoin; \
    install -d -o 1000 -g 1000 /home/bitcoin /home/bitcoin/.bitcoin /opt/bitcoind/lib

COPY --from=build /out/bin/bitcoind /usr/local/bin/bitcoind
COPY --from=build /out/bin/bitcoin-cli /usr/local/bin/bitcoin-cli
COPY --from=build /out/lib/ /opt/bitcoind/lib/
ENV LD_LIBRARY_PATH=/opt/bitcoind/lib

USER bitcoin
WORKDIR /home/bitcoin
# declared so a fresh volume inherits the 1000:1000 ownership set above
VOLUME /home/bitcoin/.bitcoin
EXPOSE 8332 8333
ENTRYPOINT ["bitcoind"]
CMD ["-printtoconsole"]
