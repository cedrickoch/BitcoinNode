# Pre-change baseline

Captured for the rollback proof required by `quickstart.md` P-0 and for the
before/after comparison in later phases.

**Capture environment**: planning/implementation sandbox has no Docker daemon and no
outbound DNS. Items marked `[device]` were not executable here; they are run once on
the Pi before the first compose change and pasted below. Static items were measured
by reading the repository and are complete.

## Repository state

- HEAD at start of implementation: `cfcd301` (`harden compose overlays, pin node image, retire miner overlay`)
- Working tree at start: untracked `.pi/`, `.specify/`, `docs/hardening-baseline.md`,
  `scripts/`, `specs/`, `docker/bitcoind/{fetch-keys.sh,keys/,.dockerignore}`,
  `docker/tor/{.dockerignore,README.md}`

## Static measurement (complete)

| Item | Value |
| --- | --- |
| Services in `docker-compose.yml` | 15 |
| Host-published ports | 80, 3000, 3333, 3334, 50001, 8501 |
| Host-published ports, testnet4 | 80, 3000, 40001, 44224, 9090 |
| Host-published ports, private (stacked) | inherits default mode |
| Host-published ports, import | none |
| Services with `read_only: true` | 1 (`grafana`) |
| Services with non-root `user:` | 4 (`electrs`, `web`, `api`, `bitcoind_exporter`) |
| Services with `healthcheck` | 0 |
| Services with `logging` limits | 0 |
| Floating/untagged image references | 7 (`mariadb`, `grafana/grafana:latest`, `prom/prometheus:latest`, `prom/node-exporter:latest`, `quay.io/prometheuscommunity/json-exporter:latest`, `ghcr.io/primexz/bitcoind-exporter:latest`, `gcr.io/cadvisor/cadvisor:latest`) |
| Committed database credentials | `MYSQL_PASSWORD: "mempool"`, `MYSQL_ROOT_PASSWORD: "admin"` in 2 files |
| Networks per service | all on `default`; `core` used by `bitcoin`, `electrs`, `api`, `public-pool`, `bitcoind_exporter` |
| RPC publish | `8332` published on `bitcoin` in default and testnet4 (import has none) |
| `check-overlay-parity.sh` result | not run (`[device]`, needs `awk` only — actually host-runnable) |

## `[device]` captures — run on the Pi before the first change

Paste each block under its heading.

### `docker compose config` (all four modes)

```sh
docker compose config > /tmp/before-default.yml
docker compose -f docker-compose-testnet4.yml config > /tmp/before-testnet4.yml
docker compose -f docker-compose-import.yml config > /tmp/before-import.yml
docker compose -f docker-compose.yml -f docker-compose.private.yml config > /tmp/before-private.yml
```

### Outside-in port scan

```sh
# from a second machine on the same LAN
nmap -Pn -p- <node-ip>
```

### Container inspection

```sh
docker compose ps -q | xargs docker inspect > /tmp/before-inspect.json
```

### Parity checker

```sh
scripts/check-overlay-parity.sh --verbose
```

## Results log

Filled in by the verification task of each phase (T017, T024, T033, T039) and by
the polish pass (T040–T046).

## Phase 3 (US1 exposure) — static verification

| Check | Result |
| --- | --- |
| `8332` publish removed from `bitcoin` (default, testnet4) | pass (grep clean) |
| RPC bound to `127.0.0.1` + `172.28.0.2` | pass in default, testnet4, private |
| `-rpcallowip` keeps `127.0.0.1` and the core CIDR | pass |
| `db` on `explorer` only | pass |
| `web` on `explorer` only | pass |
| `api` on `core` + `explorer` | pass |
| `db`, `grafana`, `node_exporter`, `json_exporter`, `cadvisor`, `btctrack` off `core` | pass |
| `public-pool`, `electrs`, `bitcoind_exporter` still on `core` (they need RPC/P2P) | pass |
| YAML structure (indent, duplicate keys) | pass |
| `scripts/check-overlay-parity.sh` | OK, 0 drift |

`[device]` outstanding: `nmap` scan, `ss -ltnp`, `docker inspect` membership dump,
explorer block advance, `docker compose config` for all four modes.

## Phase 4 (US2 secrets) — static verification

| Check | Result |
| --- | --- |
| No committed literal password in compose | pass (`mempool`/`admin` only remain as DB/user names) |
| Compose uses `${VAR:?}` for both DB passwords, on producer and consumer | pass |
| `generate-secrets.sh` creates `.env` mode 600 | pass |
| Idempotent, never overwrites | pass (value preserved across runs) |
| Re-fills a blanked value | pass |
| Warns per generated value, never prints a value | pass |
| `install.sh` generates before the first container | pass |

`[device]` outstanding: old literals rejected by the database, rotation keeps the
explorer working, no secret in `docker compose logs`.

## Phase 5 (US3 trust & posture) — static verification

| Check | Result |
| --- | --- |
| `docs/trust.md` lists every image and the snapshot | pass (13 image rows + 1 data row) |
| No `:latest` or untagged image in any compose file | pass |
| Every entry has a refresh trigger | pass |
| Snapshot row states the basis is `none at transfer time` | pass |
| Height hash check documented in `trust.md` and README | pass |
| `refresh-images.sh` flags unpinned refs, exit 1 | pass |
| `audit-hardening.sh` parses the deviation table | pass (17 rows parsed) |
| Audit reports `deviated` for a documented deviation | pass (fake docker: db cap_add/read_only/user) |
| Audit reports `DRIFT` for an undocumented one | pass (web read_only before the row existed) |
| `read_only` added where tolerated | pass (9 default, 6 testnet4) |
| `user` non-root where safe, deviation row otherwise | pass |

`[device]` outstanding: each `read_only` service actually starts; prometheus
volume ownership; injected-drift and removed-deviation cases; snapshot hash match
after a real import.

## Phase 6 (US4 health & logs) — static verification

| Check | Result |
| --- | --- |
| healthcheck present on every long-running service | pass (13 default, 9 testnet4, 1 tor) |
| probes are functional, not process-liveness | pass (chain synced, index served, API queried, SQL accepted) |
| `depends_on: condition: service_healthy` on hard deps | pass (electrs→bitcoin, api→db, web→db, bitcoind_exporter→bitcoin, tor→bitcoin) |
| `security-status.sh` renders per-service + overall verdict | pass (fake docker: healthy + unhealthy, exit 1) |
| first-diagnostic step documented per service | pass |
| log bounds present (Phase 2 T009) | pass, 13 blocks |

`[device]` outstanding: real probes reach healthy; `bitcoin` stop marks dependents
not-healthy; log cap observed; cadvisor/json_exporter probe forms confirmed.

## Phase 7 (polish) — static verification

| Check | Result |
| --- | --- |
| `check-overlay-parity.sh` clean | pass, 0 drift (regression re-tested by deleting a `read_only`) |
| YAML structure all four files | pass |
| SVG validity | pass, both diagrams |
| All scripts shell-syntax clean | pass |
| Two new docs cross-linked with the baseline | pass |
| Diagrams show RPC not published, three networks | pass |
| Import mode healthcheck opt-out recorded in the overlay | pass |

`[device]`: private-mode pass, rollback rehearsal, whole-quickstart walkthrough.

## Post-verification fix (2026-11-27)

`docker compose -f docker-compose-testnet4.yml up bitcoin` failed with
`services.bitcoin.healthcheck.test.1 must be a string`: the inner `"` in
`grep -q 'initialblockdownload": false'` was unescaped and terminated the YAML
double-quoted scalar. Escaped in both files, and `scripts/check-compose-syntax.sh`
was added so the class of error fails a check instead of `up`. Re-tested by
re-introducing the bug (checker fails) and removing it again (checker passes).

My earlier key/indent scan did not model quotes, which is why it reported OK.
