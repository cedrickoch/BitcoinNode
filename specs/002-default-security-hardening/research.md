# Phase 0 Research: Default Stack Security Hardening

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

The spec carried no `[NEEDS CLARIFICATION]` markers into planning; the
clarification session resolved the five decision points it had (recorded in
`spec.md` → Clarifications). This document resolves the *technical* unknowns the
plan needs, and states, for each, what evidence exists and what must still be
confirmed on device.

**Evidence constraint**: this planning environment has no Docker daemon and no
outbound DNS, so no endpoint, binary, or registry tag below could be *executed*
here. Each item therefore carries an explicit on-device confirmation step, and the
plan's first task phase confirms them before anything is built on top. Where a
probe cannot be confirmed, the documented fallback rule applies rather than
silently shipping a check that always fails.

---

## R-01 — How to stop publishing the node's control port

**Decision**: Stop publishing RPC to the host. `bitcoind` binds it to two
addresses inside the container — `127.0.0.1` (used by the Tor container, which
shares the namespace, and by the one-shot import) and the container's fixed core
address `172.28.0.2` — and keeps `-rpcallowip=172.28.0.0/24`. The bitcoin service
gets a static address in the `core` subnet via `ipam`; consumers keep dynamic
addresses and remain covered by the CIDR.

**Rationale**: This is the only shape that satisfies FR-002 *and* FR-003 together.
Loopback alone would force every consumer into the node's namespace, which in turn
forces every published port onto the node service and collapses the network split.
Binding to the named interface plus loopback is genuinely narrow, survives the
stacked private overlay (the Tor container needs loopback in the shared namespace),
and keeps the existing `-rpcallowip` CIDR meaningful instead of decorative.

**Alternatives considered**:
- *Leave `-rpcbind=0.0.0.0` on one flat network* — rejected: any container, and
  the host, keeps reaching RPC; FR-004 unmet.
- *Put all consumers in `network_mode: "service:bitcoin"`* — rejected: publishes
  `80`, `3000`, `3333`, `3334`, `50001` from the node service, entangles every
  restart, and makes per-service `read_only`/`user:` changes harder to reason about.
- *Drop `-rpcallowip` and rely on loopback only* — rejected: the explorer and
  miner pool stop working (they are separate namespaces in this design).

**Verify on device**: `docker compose exec bitcoin bitcoin-cli getnetworkinfo`
shows the RPC port bound to `127.0.0.1` and `172.28.0.2` only;
`ss -ltnp` on the host shows no `8332`; explorer blocks list and a miner
connection both still work.

## R-02 — Network layout for the explorer and monitoring planes

**Decision**: Three networks. `core` `172.28.0.0/24` = bitcoind, electrs,
api, public-pool, bitcoind_exporter. `explorer` `172.29.0.0/24` = api, web, db.
`default` = the monitoring plane (prometheus, node_exporter, cadvisor,
json_exporter, grafana, btctrack). `db` must join `explorer` only; this is the
one service whose membership is load-bearing (R-04 depends on it).

**Rationale**: Directly implements FR-004. It also shrinks what a compromised
explorer container can reach to the RPC network it legitimately needs, while the
database stops being reachable from the RPC network at all.

**Alternatives considered**: two networks (`core` + everything else) — rejected:
`db` would stay reachable from the RPC plane, and monitoring would sit on it.
One network with `-rpcallowip` restricted per address — rejected: `-rpcallowip`
accepts CIDRs and single addresses, so this is viable but needs manual IP
bookkeeping for every consumer and gives no structural guarantee.

**Verify on device**: `docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'` on each container matches the table in R-02 exactly;
`docker compose exec db` cannot reach `bitcoin:8332`.

## R-03 — Probe binary and functional endpoint per service

**Decision**: Per-service health probes, each aimed at the service's own function,
using a binary confirmed present in that image. Fallback rule: if neither `sh` nor
a fetcher exists, the check degrades to a documented, functional-as-possible form
and the limitation is recorded in the baseline's deviation table (FR-018).

| Service | Probe | Confirmation needed |
| --- | --- | --- |
| `bitcoin` | `bitcoin-cli getblockchaininfo` succeeds and `initialblockdownload` is `false` (Debian slim image → `sh` + `grep` available) | command runs as uid 1000 against the cookie |
| `electrs` | HTTP GET `localhost:4224/` returns 200 (monitoring endpoint already scraped) | `curl` or `wget` present in `4324363/electrs` |
| `web` | `wget -qO- localhost:8080/` returns 200 (nginx alpine has busybox wget) | wget present |
| `api` | GET `localhost:8999/api/v1/blocks` returns 200 | port is 8999 and `curl`/`wget` present |
| `db` | `healthcheck.sh --connect --innodb_initialized` (shipped by MariaDB 11.x) | script present at that path |
| `grafana` | `wget -qO- localhost:3000/api/health` | wget present |
| `prometheus` | `wget -qO- localhost:9090/-/ready` | wget present |
| `node_exporter` | `wget -qO- localhost:9100/metrics` | wget present |
| `json_exporter` | `wget -qO- localhost:7979/-/healthy` | endpoint exists; else `/metrics` |
| `bitcoind_exporter` | `wget -qO- localhost:9332/metrics` | wget present |
| `cadvisor` | HTTP GET `localhost:8080/healthz` | **at risk**: distroless base has no shell or fetcher; if so, fall back to `["CMD","/usr/bin/cadvisor","-h"]` and record as deviation |
| `public-pool` | GET the API port root | port is `3334`; `curl`/`wget` present in the Node image |
| `btctrack` | GET `localhost:8501/` returns 200 | fetcher present in the image |
| `tor` | TCP accept on `127.0.0.1:9050` inside bitcoind's namespace (`nc -z` via busybox) | `nc` present in Alpine base |

**Rationale**: FR-014 asks for functional, not process-liveness, checks — a
`pgrep`-style probe cannot distinguish a stalled node from a synced one, which is
exactly the failure the story exists to catch. Target endpoints are chosen from
what the stack already exposes (metrics endpoints, the readiness endpoint, the
health API) rather than by adding new ones.

**Alternatives considered**: a TCP-connect check on every service — rejected, it
passes on a wedged process; a single external prober container — rejected, it is
a new service against Principle I.

**Timing**: `interval: 30s`, `timeout: 10s`, `retries: 3`, `start_period: 300s`
for bitcoind/electrs/api (first-run volume work), `120s` for the rest,
`60s`/`interval 10s` for tor.

**Verify on device**: `docker inspect --format '{{.State.Health.Status}}'` on
every container reaches `healthy`; stop `bitcoin` and confirm `electrs`, `api`,
`bitcoind_exporter` leave `healthy`.

## R-04 — Which services tolerate `read_only: true`

**Decision**: Add `read_only: true` with the needed `tmpfs` where the service
writes elsewhere anyway; keep the existing justified exception.

| Decision | Services |
| --- | --- |
| `read_only: true` + tmpfs | `web` (tmpfs `/var/cache/nginx`, `/var/run`), `api` (tmpfs `/tmp`), `prometheus` (tmpfs `/tmp`), `node_exporter`, `cadvisor`, `bitcoind_exporter`, `json_exporter`, `btctrack` (tmpfs `/tmp`), `electrs` (tmpfs `/tmp`) |
| already read-only | `grafana`, `tor` |
| stays writable, documented | `db` (entrypoint writes before the volume is ready), `bitcoin` (data dir + cookie churn), `public-pool` (writes its own app dir), `mariadb`-hosted `db` volume |

**Rationale**: FR-017/FR-018 push toward the maximum tolerated set with the
remainder recorded. Every writable root is currently an unexplained gap, which is
worse than a small, enumerated exception list.

**Alternatives considered**: only read-only where zero risk — rejected, it leaves
the baseline mostly unapplied and the audit meaningless; read-only everywhere with
`tmpfs` for the whole filesystem tree — rejected for `bitcoin`/`db`, whose
entrypoints write outside their volumes on first start.

**Verify on device**: each affected container reaches `healthy` with `read_only`
set; `docker inspect` reports `ReadonlyRootfs: true`; the explorer still renders
and `api` still writes its cache volume.

## R-05 — Exact image versions to replace the floating tags

**Decision**: Pin the seven floating references to exact versions:
`mariadb:11.4`, `grafana/grafana:11.3.1`, `prom/prometheus:v3.1.0`,
`prom/node-exporter:v1.8.2`, `quay.io/prometheuscommunity/json-exporter:v0.6.0`,
`ghcr.io/primexz/bitcoind-exporter:v0.5.0`, `gcr.io/cadvisor/cadvisor:v0.49.1`.

**Rationale**: Principle VI forbids `latest`-only and the baseline tolerates
floating tags only as a concession. Exact tags make a binary swap impossible
without a commit, which is what FR-011 asks for in place of an implicit pull.

**Alternatives considered**: digest pinning — preferred by the constitution "where
available", but a digest must be read from the device's registry response, so it
is recorded as a follow-up rather than guessed here; leaving `latest` plus a
`--pull` ritual — rejected, unchanged risk.

**Verify on device**: `docker compose pull` resolves all seven; `docker compose
config --images` lists no `:latest` and no untagged reference.

## R-06 — How secrets reach the containers without landing in output

**Decision**: `.env` (gitignored) is the only source. Compose references use
`:?` so a blank value fails the start loudly; `scripts/generate-secrets.sh`
writes random values into an existing `.env` or copies `.env.example` first, is
idempotent, never overwrites, and prints one warning line per generated value.
`install.sh` invokes it before the first `up`. No secret is echoed by any script
after generation.

**Rationale**: Satisfies FR-005/FR-006/FR-007/FR-009 at once. `:?` keeps the
fail-closed behaviour while the generator removes the deadlock, and warning lines
carry only names — never values — so they are safe to paste into an issue.

**Alternatives considered**: compose `default:` values — rejected, they are
committed strings and therefore the exact problem being fixed; Docker secrets —
rejected, they need Swarm or file mounts and add a second source of truth for a
single-operator box; generating at container start — rejected, `db` only honours
`MYSQL_PASSWORD` on first initialisation, so the value must exist before the
container is created.

## R-07 — Credential rotation that does not lose explorer data

**Decision**: `scripts/rotate-db-password.sh` → read the old value from `.env`,
`ALTER USER 'mempool'@'%' IDENTIFIED BY '<new>'` inside the running `db`, write
the new value to `.env`, restart `api` and `web`. The root password is rotated the
same way. Refuse to run when the stack is down, since the command must execute
against a live database.

**Rationale**: Accomplishes the clarified answer (one command, both sides in step,
data kept). Order is forced by MariaDB semantics: the grant is the authority, so
it changes first; the consumer restarts after.

**Alternatives considered**: change `.env` and recreate the volume — rejected,
loses explorer statistics; `--env-file` swap without an `ALTER USER` — rejected,
the database keeps the old grants and the explorer cannot log in.

**Verify on device**: rotate, confirm `api` healthy and blocks still render, then
rotate back and confirm the same.

## R-08 — Snapshot verification without a published checksum

**Decision**: Post-import the operator runs `bitcoin-cli getblockhash <height>`
for the snapshot's stated height (840000) and compares it with the hash published
in `docs/trust.md`; a mismatch means the import is not trusted and the node is
re-imported or re-synced from scratch. `docs/trust.md` states explicitly that a
transfer checksum, if one is offered later, only proves the file arrived unaltered.

**Rationale**: The chain's own accumulated work is the only proof available for a
UTXO snapshot; a hash at a known height *is* that proof, and comparing it is a
one-line check.

**Alternatives considered**: trust the source URL — rejected by FR-012; hash the
`.dat` file — rejected as insufficient on its own and no authoritative file hash is
published.

**Verify on device**: run the check against a completed import; the hash matches
the recorded value.

## R-09 — Bounding logs

**Decision**: A per-service `logging:` block — `driver: json-file`,
`max-size: 10m`, `max-file: "3"` (30 MB/service, ~450 MB worst case across the
stack) — applied to every service in all four files; `check-overlay-parity.sh`
compares `logging` so overlays cannot omit it.

**Rationale**: FR-016 / SC-006 need a shipped bound, and Docker's default is
unbounded. A 32 GB SD card cannot absorb an unattended month of `bitcoind`
debug output.

**Alternatives considered**: a global `daemon.json` setting — rejected, it is host
configuration the compose files cannot carry and that the README would have to
duplicate; driver change to `journald`/`local` — rejected, `local` is fine but
`journald` needs host config and both make the documented `docker logs`
diagnostics less predictable.

## R-10 — Consistency with the existing parity checker

**Decision**: Extend `CHECKED_KEYS` with `healthcheck` and `logging`, and have
`scripts/audit-hardening.sh` read the deviation table from
`docs/hardening-baseline.md`.

**Rationale**: The checker exists precisely so the standalone overlays cannot
diverge (FR-012 of the prior feature). Adding the two new cross-cutting keys keeps
that guarantee intact; making deviations data keeps FR-018 checkable.

**Alternatives considered**: rely on review — rejected, that is what the checker
already replaced; a second, separate script — rejected as duplicate machinery.

**Verify on device**: `scripts/check-overlay-parity.sh --verbose` reports `OK` for
all overlays after the changes; injecting a removed `healthcheck` into one overlay
makes it fail.
