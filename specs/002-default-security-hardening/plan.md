# Implementation Plan: Default Stack Security Hardening

**Branch**: `002-default-security-hardening` | **Date**: 2026-11-27 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-default-security-hardening/spec.md`

## Summary

The overlay-parity feature (`specs/001-overlay-parity`) made hardening a written
baseline and made drift checkable, but it aligned the *overlays* to the default
mode. The default mode itself — the reference every other mode copies — still has
never had a hardening work item. This plan closes it, in the order the spec ranks
the value: narrow the surfaces first, then remove known passwords, then write down
the trust the stack places in third parties and give the operator a standing view
of the hardening posture, and finally replace liveness with health.

Measured starting point (default mode, 2026-11-27), all confirmed by reading the
repository:

- 15 long-running services; 7 host-published ports; the node's RPC port
  published to the LAN; every service on one flat `default` network.
- `MYSQL_ROOT_PASSWORD: "admin"` and `MYSQL_PASSWORD: "mempool"` committed to two
  compose files; `.env.example` covers only the Tor password.
- 7 floating `:latest`/untagged images; no trust record; the snapshot is loaded
  with no integrity step at all.
- 1 of 15 services is `read_only`; 4 pin a non-root `user:`; zero healthchecks;
  zero log bounds; zero standing security view.

Approach: one new operator-facing command set (generate secrets, rotate, status,
audit, refresh), two new reference documents (exposure table, trust record), and
compose changes across the default mode, the two standalone overlays, and the one
stacked overlay — kept in lockstep by the existing parity checker, which is
extended to compare healthchecks and log bounds too.

## Technical Context

**Language/Version**: Compose Specification v2 (`docker compose` v2 CLI); POSIX
`sh` for the new scripts, matching the existing `scripts/*.sh` convention

**Primary Dependencies**: Docker Engine with the compose v2 plugin; `openssl` for
secret generation; `awk`/`sed` for the audit and parity scripts (already a
checker dependency); `curl`/`wget` inside containers for probes (each verified
present in the image before being relied on)

**Storage**: Named Docker volumes (`bitcoin_data`, `mempool_db`, …) — names and
mount paths unchanged so existing chain data survives. New: `.env` becomes the
credential store (gitignored already) and is added to the documented backup scope.

**Testing**: Manual and repeatable, as the project has no pipeline. Validation is
`docker compose config` per shipped mode, `scripts/check-overlay-parity.sh` (run
with `--verbose`), `scripts/audit-hardening.sh`, `scripts/security-status.sh`,
`docker inspect`, and per-story scenarios in `quickstart.md`. Note: this sandbox
has **no Docker**, so every container-level assertion below is executed on the Pi.

**Target Platform**: Raspberry Pi / Raspberry Pi OS, arm64, single operator

**Project Type**: Deployment/configuration repository (compose stack + ops
scripts), not an application codebase

**Performance Goals**: Parity check < 1 min (existing contract); audit view < 10 s
for 15 services; status view completes while the stack is degraded, with probes
timed out so a hung service cannot stall it

**Constraints**: arm64 only; zero new host-published ports; private (Tor) mode
must keep working; fresh install must still start; existing volumes must not be
recreated; hardening may not be achieved by removing a documented feature

**Scale/Scope**: 4 compose files, ~15 services, 2 new docs, 5 new scripts, 1
extended checker; single operator, home LAN

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Status |
|-----------|------|--------|
| I. Simplicity First | Five small scripts, no new service; each has an operator-facing purpose | PASS |
| II. Container-First Deployment | All behaviour stays in compose + scripts; only numbered README steps are host-level | PASS |
| III. Privacy & Sovereignty | Tor overlay untouched in topology; onion reachability preserved (FR-021); no third-party lookup introduced | PASS |
| IV. Security by Least Exposure | This feature *is* the IV work on the default mode: loopback RPC, network split, read-only, `user:`, pids, documented deviations | PASS |
| V. Documentation-Driven Operations | Exposure table, trust record, per-service first-diagnostic steps, inline reasons for every deviation; same change | PASS |
| VI. Supply Chain Integrity | Exact version tags for the 7 floating images, trust record with refresh trigger, snapshot backed by the chain's own work | PASS |
| Workflow gate "no port without a README entry" | Port table rewritten as the exposure table, with authentication column | PASS |
| Workflow gate "no weakening without a comment" | Existing justified deviations are formalised in a machine-readable list the audit reads (D-07) | PASS |

**Post-Phase-1 re-check**: unchanged — no service added or removed, no port
added, no baseline key dropped without an entry in the deviation list.

Design-time findings that had to be reconciled against the gates:

- R-03 puts a probe binary requirement on 15 images. Two (`cadvisor`, and the
  MariaDB health script) are unconfirmed without a daemon, so each carries a
  documented fallback plus a deviation row — no gate is passed on an assumption.
- R-10 makes the deviation table machine-readable. That turns the constitution's
  "no weakening without an inline comment" gate into an executable check rather
  than a review habit, so IV and the workflow gate strengthen together.
- The exposure contract moves the existing README port table into a dedicated
  document with an authentication column. Principle V is satisfied by the same
  commit, and the table gains content (FR-001a) rather than losing it.
- R-01 leaves `-rpcallowip` in place. A reviewer might expect the CIDR to be
  dropped with `rpcbind`; D-03 records why it stays so the gate reading is not
  ambiguous.

## Decisions

- **D-01 — Loopback first.** `bitcoind` drops `-rpcbind=0.0.0.0` (the image and
  the RPC clients already default to loopback and all RPC consumers join
  `bitcoind`'s network namespace or the core network). Private mode adds
  `-rpcallowip` for the container addresses it must keep. `-bind` stays for P2P;
  `public-pool` reaches the node through the shared network as today.
- **D-02 — Three networks.** `core` (172.28.0.0/24) keeps bitcoind + its RPC/P2P
  consumers; `explorer` (172.29.0.0/24) carries web↔api↔db; `default` carries the
  monitoring plane. `electrs` and `bitcoind_exporter` stay on `core`. Services
  that need nothing (`db`, `json_exporter`, `node_exporter`, `cadvisor`,
  `grafana`, `btctrack`) leave every network that carries RPC.
- **D-03 — `-rpcallowip` pinned to the core subnet** stays as-is: it is the fixed
  CIDR that was the whole point of the fixed subnet in `docker-compose.yml`.
- **D-04 — Secrets come from `.env` only**, never from compose defaults:
  `scripts/generate-secrets.sh` fills placeholders with `openssl rand -hex 24`
  when absent, is idempotent, never overwrites an operator-set value, and prints
  one `WARN` line per value it had to generate. Compose keeps `:?` fail-closed
  references so a hand-edit that blanks a value fails loudly rather than falling
  back to a known string.
- **D-05 — Rotation is one command, DB first.** `scripts/rotate-db-password.sh`
  reads the current value, runs `ALTER USER` inside the running `db`, writes the
  new value to `.env`, then restarts `api` (and `web`) so both sides agree. Chain
  data is untouched (FR-008). Order matters because `MYSQL_PASSWORD` is only
  honoured at first initialisation.
- **D-06 — Health is functional, not liveness.** Each service probes the thing it
  exists to do (see `contracts/health-probes.md`), with `start_period` long enough
  for a first-run volume. `depends_on` becomes `condition: service_healthy` for
  electrs→bitcoin, api→db, web→db, bitcoind_exporter→bitcoin, so a half-up stack
  does not manufacture confusing errors.
- **D-07 — Deviations are data.** `scripts/audit-hardening.sh` reads
  `docs/hardening-baseline.md`'s deviation table, so a documented deviation is
  reported as `deviated` rather than drift, and an *undocumented* one is an
  error. This turns FR-018 into a check instead of a promise.
- **D-08 — Floating tags become exact versions** for all 7: `mariadb:11.4`,
  `grafana/grafana:11.3.1`, `prom/prometheus:v3.1.0`, `prom/node-exporter:v1.8.2`,
  `quay.io/prometheuscommunity/json-exporter:v0.6.0`,
  `ghcr.io/primexz/bitcoind-exporter:v0.5.0`, `gcr.io/cadvisor/cadvisor:v0.49.1`.
  Confirmation of each tag on the device is a task step, since this sandbox has no
  registry access. `scripts/refresh-images.sh` reports image age, which is the
  explicit, non-silent refresh path FR-011 asks for.
- **D-09 — Snapshot trust is a hash at height.** `docs/trust.md` and the README
  give the post-import check (`getblockhash <snapshot height>` compared with the
  published hash) and state plainly that a checksum only proves the transfer.
- **D-10 — Dashboards stay unauthenticated.** Per the clarification: no dashboard
  credential. `docs/exposure.md` marks port 3000 and 80 as unauthenticated and
  says what a default view reveals.
- **D-11 — Overlays re-copy, the checker re-checks.** Both standalone overlays
  repeat every change verbatim (they are standalone by design, FR-014), the
  stacked private overlay adds only what it needs, and `check-overlay-parity.sh`
  gains `healthcheck` and `logging` in its compared key set so the copies cannot
  drift.

## Project Structure

### Documentation (this feature)

```text
specs/002-default-security-hardening/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   ├── cli-contracts.md      # new script interfaces
│   ├── exposure-contract.md  # published-port contract
│   └── health-probes.md      # per-service probe contract
├── checklists/
│   └── requirements.md  # spec quality checklist
└── tasks.md             # /speckit.tasks output
```

### Source Code (repository root)

```text
docker-compose.yml                  # default mode: networks, RPC binding,
                                    #   secrets from .env, healthchecks, log
                                    #   bounds, read_only/user tightening, pins
docker-compose-testnet4.yml         # same, standalone (ports 40001/44224/9090)
docker-compose-import.yml           # same, one-shot; no secrets, no health
docker-compose.private.yml          # stacked: -rpcallowip for the container, tor
                                    #   healthcheck
.env.example                        # every secret as an empty placeholder
scripts/generate-secrets.sh         # new: fill placeholders, warn
scripts/rotate-db-password.sh       # new: one-command rotation
scripts/security-status.sh          # new: per-service + overall verdict
scripts/audit-hardening.sh          # new: baseline view, reads deviation list
scripts/refresh-images.sh           # new: image age + deliberate --pull
scripts/check-overlay-parity.sh     # extended: healthcheck, logging
docs/exposure.md                    # new: canonical port table + exposure notes
docs/trust.md                       # new: trust record + snapshot verification
docs/hardening-baseline.md          # extended: deviation table becomes data
README.md                           # exposure table, first-run secrets, rotate,
                                    #   status, refresh/rollback, snapshot check
install.sh                          # call generate-secrets.sh before any start
```

**Structure Decision**: the flat repository layout stays. Operator-facing
documents go under `docs/` (where the hardening baseline already lives) and
executables under `scripts/` (where the parity checker already lives); no new
root-level files beyond the existing compose set.

## Phase Plan

- **Phase 0 (research)**: pin the health endpoint per service, the probe binary
  present in each image, the read-only tolerance per service, the exact image
  versions, and the network split's effect on `-rpcallowip`. Output `research.md`.
- **Phase 1 (design)**: entities and validation rules (`data-model.md`), the three
  contracts, the validation runbook (`quickstart.md`), constitution re-check.
- **Phases 2-5**: one phase per user story in priority order (exposure, secrets,
  trust + posture, health + log bounds), each ending in its own verification.
- **Phase 6**: polish — parity checker extension, docs cross-links, README
  consistency, rollback rehearsal.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Three networks instead of one | FR-002/FR-004 require RPC to be reachable only by its consumers | One flat network leaves the explorer facing the node's control port; a second network alone still leaves db and exporters on the RPC network |
| Five new scripts | FR-005/008/015/017/013 each demand a repeatable command an operator runs | Documented one-off command sequences drift and cannot be asserted by the audit; the parity checker already established scripts as the project's mechanism |
| Deviation list parsed by the audit | FR-018 demands deviations be recorded, not silently omitted | A prose-only list decays and cannot fail a check; parsing the table keeps one source of truth |
| Healthchecks require probe binaries in 15 images | FR-014 requires functional health | Process-only checks cannot tell a stalled node from a synced one, which is the failure the story exists to catch |

## Rollback

Each phase is independently revertible by `git revert` of its commit. Compose
reverts restore the previous containers on `docker compose up -d`; `.env` keeps
its generated values, which the reverted compose still reads through the same
variable names. Chain data is never touched. A credential rotation is revertible
by running the rotation command with the previous value.
