# self-built bitcoind

Multi-stage build: GPG-verified Bitcoin Core source -> depends (boost via
CMake, libevent) -> slim runtime image running as uid 1000, no capabilities
required. The boost/libevent shared libs are copied into /opt/bitcoind/lib
if anything links them dynamically.

## Build (on the ARM Mac, native arm64)

```sh
docker buildx build --platform linux/arm64 --load -t 4324363/bitcoind:32.1 .
```

Note the trailing `.` (build context = this directory).

Takes roughly 45-70 min and ~3 GB disk on an M-series Mac.

## Smoke-test before pushing

```sh
docker run --rm 4324363/bitcoind:32.1 -version

# throwaway datadir, quick chain init:
docker run --rm 4324363/bitcoind:32.1 -regtest -printtoconsole \
  | grep -m1 "Done loading" && echo OK
```

## Push

```sh
docker push 4324363/bitcoind:32.1
```

## Switch the stack (on the Pi)

In all compose files using `bitcoin/bitcoin`, replace the bitcoin service with:

```yaml
bitcoin:
    image: 4324363/bitcoind:32.1
    container_name: bitcoind
    volumes:
        - bitcoin_data:/home/bitcoin/.bitcoin
    networks:
        - core
    cap_drop: [ALL]            # no cap_add at all anymore
    security_opt: ["no-new-privileges:true"]
    pids_limit: 300
    # no mem_limit: initial block sync has RAM spikes
    command: ["-rpcbind=0.0.0.0", "-rpcallowip=172.28.0.0/24", "-txindex=1"]
```

Removed vs the old config:

- `UID`/`GID` env — image runs as uid 1000 by default
- `cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID]` — no root entrypoint
  dance, nothing to chmod/chown
- Roll out on testnet4 first (throwaway data), then main.

The existing `bitcoin_data` volume is already owned by uid 1000, so it keeps
working unchanged.

## Version bumps

- Change `ARG BITCOIN_VERSION` (and the image tag), check the signer list at
  `https://bitcoincore.org/bin/bitcoin-core-<version>/` and update
  `MAINTAINER_KEYS` if it changed.
- Verification is fail-closed: a bad or missing signature aborts the build.
  It requires at least one good signature from a pinned maintainer key;
  signatures from other builders are ignored (their keys are not imported).

## Notes

- Wallet support is disabled (`-DENABLE_WALLET=OFF`): the node runs watch-only
  behind electrs/mempool. Re-enable by removing that flag (plus `NO_WALLET=1`,
  and add `-DENABLE_SQLITE=ON`).
- Core >= 29 is CMake-only; the build step auto-detects `CMakeLists.txt` and
  falls back to autotools for older tarballs. Compilers come from the depends
  toolchain file, libs are linked statically by depends.
- A `depends` build is not bit-for-bit reproducible like the official guix
  releases — trust rests on the GPG-verified source plus your own build.
- Rollback = `git revert` the compose change; the old `bitcoin/bitcoin` image
  is still on the Pi.
