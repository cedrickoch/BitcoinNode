# Container hardening baseline

This is the canonical hardening baseline for every service in this repository.
It is the written form of constitution principles IV (Security by Least Exposure)
and VI (Supply Chain Integrity). `docker-compose.yml` is the reference
implementation; overlays copy it.

Enforced by `scripts/check-overlay-parity.sh` (drift), `scripts/check-compose-syntax.sh`
(flow/quote syntax) and `scripts/audit-hardening.sh` (live posture, reads the
deviation table below). Run them before every commit that touches a compose file.

Related: [exposure](exposure.md) · [trust record](trust.md).

## Required per service

| Key | Requirement |
| --- | --- |
| `cap_drop` | MUST be `[ALL]` |
| `cap_add` | MUST be empty, or the documented minimum, with an inline comment naming the reason |
| `security_opt` | MUST include `"no-new-privileges:true"` |
| `pids_limit` | MUST be set, sized to the service (see the base file for the per-service values) |
| `read_only` | MUST be `true` where the service tolerates a read-only root filesystem, together with a `tmpfs` mount for whatever it needs to write |
| `user` | MUST be non-root, unless a documented entrypoint needs root to prepare the data directory and then drops privileges |
| `healthcheck` | MUST probe the service's actual function (see `specs/002-default-security-hardening/contracts/health-probes.md`), with a `start_period` long enough for a first-run volume |
| `logging` | MUST bound growth (`json-file`, `max-size: 10m`, `max-file: "3"`) so an unattended run cannot fill the card |

`mem_limit` is deliberately **not** part of the baseline: initial block sync,
snapshot import, and electrs indexing all spike well past any sane cap, and a
limit there causes more outages than it prevents.

## Networks

Three networks, narrowest first:

| Network | Subnet | Carries |
| --- | --- | --- |
| `core` | `172.28.0.0/24` | bitcoind, and only the services that use its RPC or P2P · `bitcoin` holds the fixed address `172.28.0.2` |
| `explorer` | `172.29.0.0/24` | web, api, db — the explorer plane, no node RPC |
| `default` | engine-assigned | the monitoring plane; nothing here reaches RPC |

`bitcoind` binds RPC to `127.0.0.1` and `172.28.0.2` only, and publishes nothing.
A service belongs on `core` only if it needs RPC/P2P; an unexplained member is a
defect, not a convenience.

## Overlays are standalone, not stacked

Each overlay defines whole services and is brought up on its own, without
`docker-compose.yml`:

```sh
docker compose -f docker-compose-testnet4.yml up -d
docker compose -f docker-compose-import.yml up
docker compose -f docker-compose.yml -f docker-compose.private.yml up -d   # exception, see below
```

Because of this, an overlay inherits **nothing**. It MUST repeat the full
baseline for every service it defines. A fix made only in `docker-compose.yml`
does not reach an overlay, which is exactly the drift `scripts/check-overlay-parity.sh`
exists to catch.

`docker-compose.private.yml` is the one true overlay: it is documented and intended
to be stacked on the base file, so it only needs to add what it changes.

**Never combine two standalone overlays.** Each defines the whole stack and they
share the same volume names, so the second would silently reconfigure the first.

## What may legitimately differ per file

The checker compares these keys only for **presence**, never for equality:

- `image` — compared per service, but only for presence in the overlay; it must
  then equal the base value for that service (see below)
- `ports` — each mode exposes its own port set; no mode may add a port the
  baseline mode does not already publish, except the documented per-mode pushes
- `command` — each mode passes its own flags

Everything else in the table above must match.

## Images

Overlays MUST use the same image reference as the base file for the same service.
`bitcoind` and `electrs` are built and pushed by the project
(`4324363/*`) from GPG-verified source, so a legacy third-party node image in an
overlay means that mode is running an unverified binary. See
`docker/bitcoind/README.md` for the build and version-bump procedure.

Floating tags (`*:latest`) are tolerated for the upstream monitoring and explorer
images the base already uses, and MUST be refreshed deliberately with `--pull`.
They are not tolerated for `bitcoind` or `electrs`.

## Data

All modes mount the node data at `/home/bitcoin/.bitcoin` in the `bitcoin_data`
volume. Test network and mainnet data therefore share one volume: switching
between them re-syncs rather than merging, which is acceptable because the test
network is a throwaway mode.

The older `lncm/bitcoind` images used `/data/.bitcoin`. If a volume was created
under one of those, re-point the mount to `/data/.bitcoin` or re-sync from
scratch; do not assume the node will find data left by a different image.

## Justified deviations in this repository

This table is **data**: `scripts/audit-hardening.sh` parses it. A deviation that is
not listed here is reported as `DRIFT`; a row whose deviation no longer exists is
reported as `stale-deviation`. Any new deviation needs an inline compose comment
*and* a row here.

| service | key | reason |
| --- | --- | --- |
| `bitcoin` | `cap_add` (CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID) | the image entrypoint starts as root, prepares/chowns the data directory, then drops to the service user; removing these breaks first start on a fresh volume |
| `bitcoin` | `user` | same root entrypoint, which drops privileges itself; it cannot start as a non-root user before the volume is owned correctly |
| `bitcoin` | `read_only` | the data directory and the rotating `.cookie` are written under the mount, and bitcoind writes `bitcoin.conf.d`/debug output beside them |
| `db` | `cap_add` (CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID) | the MariaDB entrypoint starts as root, chowns the data directory and drops to the `mysql` user |
| `db` | `user` | same root entrypoint; it must own `/var/lib/mysql` before dropping |
| `db` | `read_only` | the entrypoint writes to the root filesystem before the data directory is initialised |
| `public-pool` | `cap_add` (DAC_READ_SEARCH) | runs as root to read the mode-0600 bitcoind cookie owned by uid 1000; read-only bypass only, so app-directory writes stay owner-based |
| `public-pool` | `user` | needs to read a cookie file it does not own |
| `public-pool` | `read_only` | writes into its own `/public-pool` application directory |
| `prometheus` | `user` | hardcoded to `65534` (`nobody`); the `prometheus_data` volume must be owned by 65534 — see the README, the volume is chowned on first create |
| `node_exporter` | `user` | host-metrics mode needs broad read access that a mapped uid does not get on `/proc` and `/sys` |
| `cadvisor` | `user` | needs the same host read access plus `/var/lib/docker`; the image starts as root by design |
| `btctrack` | `user` | the app writes its SQLite file into `/app/data` and ships no non-root user |
| `json_exporter` | `healthcheck` | the Dev Container/dashboard pairing has no shell or HTTP client in the image to probe with (see `research.md` R-03); falls back to a process check |
| `cadvisor` | `healthcheck` | distroless base: no shell and no fetcher, so `/healthz` cannot be curled from inside; falls back to a process check |
