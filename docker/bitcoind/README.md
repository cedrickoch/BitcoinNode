# self-built bitcoind

Multi-stage build: GPG-verified Bitcoin Core source -> depends (boost via
CMake, libevent) -> slim runtime image running as uid 1000, no capabilities
required. boost and libevent are linked statically (the build verifies this),
so the runtime image contains only the two binaries.

## Build (on the ARM Mac, native arm64)

First time (and whenever `MAINTAINER_KEYS` change), fetch the pinned
maintainer keys and commit them. The build never contacts a keyserver:

```sh
./fetch-keys.sh          # writes keys/*.gpg, fails on fingerprint mismatch
git add keys/ && git commit -m "bitcoind: pin maintainer keys"
```

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
    stop_grace_period: 5m      # let bitcoind flush its UTXO cache on stop
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
- Verification is fail-closed: the build aborts unless at least `MIN_SIGS`
  (default 2) distinct pinned maintainers produced a valid signature on
  `SHA256SUMS`. A missing or revoked pinned key also aborts. Signatures from
  other builders are ignored because their keys are not imported.
- Optionally pin the base image by digest:
  `--build-arg BASE=debian:bookworm-slim@sha256:<digest>`. Rebuild
  regularly to pick up Debian security fixes.

## Notes

- Wallet support is disabled (`-DENABLE_WALLET=OFF`): the node runs watch-only
  behind electrs/mempool. Re-enable by removing that flag (plus `NO_WALLET=1`,
  and add `-DENABLE_SQLITE=ON`).
- Only Core >= 29 (CMake) is supported; older tarballs fail early.
  Compilers come from the depends toolchain file. boost and libevent are
  linked statically, and the build fails if they show up as dynamic libs.
- The build checks that the binaries are PIE, use full RELRO/BIND_NOW, have
  a non-executable stack and use the stack protector. It also checks that
  `bitcoind -version` reports the expected version.
- The target triple comes from `--platform` (arm64 or amd64). Only native
  builds are supported; a mismatch fails early.
- Consider pinning the pushed image by digest in compose
  (`image: 4324363/bitcoind:32.1@sha256:...`) so a re-pushed tag cannot
  silently change the binary on the Pi.
- A `depends` build is not bit-for-bit reproducible like the official guix
  releases — trust rests on the GPG-verified source plus your own build.
- Rollback = `git revert` the compose change; the old `bitcoin/bitcoin` image
  is still on the Pi.
