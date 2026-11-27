---

description: "Task list for Default Stack Security Hardening"
---

# Tasks: Default Stack Security Hardening

**Input**: Design documents from `/specs/002-default-security-hardening/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Not separate artifacts — this project has no pipeline and the plan records
verification as manual and repeatable. Each story ends in an explicit verification task
that executes its `quickstart.md` section, which is the requested validation approach.

**Organization**: Tasks are grouped by user story (P1→P4) so each is independently
implementable and verifiable. Compose changes are always made across **all four** shipped
files in the same task, because the two standalone overlays inherit nothing and
`scripts/check-overlay-parity.sh` fails on drift (prior feature FR-012/FR-014).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1 (exposure), US2 (secrets), US3 (trust & posture), US4 (health & logs)
- Exact file paths in every description

## Path Conventions

Flat deployment repository: compose files at root, scripts in `scripts/`, documents in
`docs/`. See `plan.md` → Project Structure.

## Reference facts (measured, do not re-derive)

- Default mode: 15 services, 7 host-published ports (80, 3000, 3333, 3334, 50001, 8501,
  and, in testnet4, 40001/44224/9090). `8332` and `8333` are **not** published.
- `MYSQL_PASSWORD: "mempool"` and `MYSQL_ROOT_PASSWORD: "admin"` are committed in
  `docker-compose.yml` and `docker-compose-testnet4.yml`; `.env.example` covers only
  `TOR_CONTROL_PASSWORD`.
- 1 of 15 services is `read_only` (`grafana`); 4 pin a non-root `user:`; zero healthchecks;
  zero log bounds; 7 floating tags.
- Every service is on the single `default` network today; `core` exists but carries only
  `bitcoin`, `electrs`, `api`, `public-pool`, `bitcoind_exporter`.
- `docker-compose.private.yml` is the only stacked overlay; `import` and `testnet4` are
  standalone and must repeat every baseline key.
- No Docker daemon and no DNS in the planning sandbox: R-03/R-04/R-05 confirmations run
  on the Pi (Phase 1).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Capture the before-state and replace every assumption the plan had to make
without a daemon, so later phases build on confirmed facts.

- [X] T001 Capture the pre-change state in `specs/002-default-security-hardening/baseline.md`: `docker compose config` for all four modes, `nmap -Pn -p- <node-ip>` output, full `docker inspect` of every container, `git rev-parse HEAD` — this is the rollback proof for `quickstart.md` P-0
- [ ] T002 Confirm or correct the probe endpoint and probe binary for every service in `specs/002-default-security-hardening/research.md` R-03 (notably `api` port 8999, `electrs` 4224, `cadvisor` healthz, MariaDB `healthcheck.sh`); write the confirmed value or the documented fallback into R-03
- [ ] T003 [P] Confirm or correct the `read_only` tolerance table in `research.md` R-04 by starting each candidate service in testnet4 mode with `read_only: true` and recording the result
- [ ] T004 Confirm that all seven candidate image references in `research.md` R-05 resolve (`docker manifest inspect`), and replace any that do not with the nearest real tag
- [ ] T005 Confirm `openssl`, `awk`, `sed` and `curl` availability on the Pi host and inside the affected containers, and record in `research.md` R-06 and R-09
- [X] T006 Formalise the "Justified deviations" section of `docs/hardening-baseline.md` as a parseable table with `service | key | reason` columns covering every existing deviation, citing `data-model.md` **E-06 Deviation entry.reason** (non-empty, states what breaks without it) — `scripts/audit-hardening.sh` will read it

**Checkpoint**: Every unconfirmed planning assumption is either confirmed or has a documented
fallback. T001 and T006 are done; **T002–T005 need the Pi** (no daemon or DNS in this environment)
and are the only open items — their fallbacks are already in `research.md`, so nothing downstream blocks.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The cross-cutting machinery every story is validated against.

**⚠️ CRITICAL**: Later phases are validated by these; land them first.

- [X] T007 Declare the `explorer` network (`172.29.0.0/24`) and give `bitcoin` a static `core` address in `docker-compose.yml` and `docker-compose-testnet4.yml`, per `data-model.md` **E-07 Network membership.static address**; leave membership unchanged in this task
- [X] T008 Extend `CHECKED_KEYS` in `scripts/check-overlay-parity.sh` with `healthcheck` and `logging`, and add both rows to `docs/hardening-baseline.md`, so stories 3 and 4 cannot drift out of the overlays
- [X] T009 [P] Add a `logging:` block to every service in all four compose files (`driver: json-file`, `max-size: 10m`, `max-file: "3"`) per `research.md` R-09 — lands here because the checker from T008 compares it
- [X] T010 Run `docker compose config` for all four modes and `scripts/check-overlay-parity.sh --verbose`; resolve any parse error or drift before story work (no daemon here: structure validated with a key/indent/duplicate scan plus `scripts/check-compose-syntax.sh`, `config` re-run on device)

**Checkpoint**: Networks, checker and log bounds in place; stories can proceed in priority order.

---

## Phase 3: User Story 1 - Only intended things are reachable (Priority: P1) 🎯 MVP

**Goal**: The node's control interface is reachable only by its consumers, every listener is
narrow, and the published set is documented with an authentication verdict.

**Independent Test**: `quickstart.md` P-1 — outside scan shows only documented ports, host has
no `8332`, `db`/dashboards/exporters are off the RPC network, explorer and Grafana still render.

- [X] T011 [US1] Stop publishing RPC: remove `ports:` for `8332` from `docker-compose.yml` and `docker-compose-testnet4.yml`, and change the `bitcoin` command in both to bind loopback plus the static core address (`-rpcbind=127.0.0.1 -rpcbind=172.28.0.2`) per `research.md` R-01
- [X] T012 [US1] Add `-rpcallowip=127.0.0.1` alongside the existing `172.28.0.0/24` in the `bitcoin` command of both standalone files and in `docker-compose.private.yml`, so the Tor container's loopback RPC keeps working
- [X] T013 [US1] Move memberships to the design in `data-model.md` **E-07 Network membership.members**: `db` → `explorer` only, `web` → `explorer` (+ none else), `api` → `core` + `explorer`, and take `db`, `grafana`, `node_exporter`, `json_exporter`, `cadvisor`, `btctrack` off `core` — apply identically to `docker-compose.yml` and `docker-compose-testnet4.yml`
- [X] T014 [US1] Create `docs/exposure.md` from the README port table with `port | service | purpose | authenticated | modes | narrowing` columns, honouring `data-model.md` **E-01 Exposure entry.port** (unique, one row per published port) and `data-model.md` **E-01 Exposure entry.authenticated** (enum `yes`/`no`/`same-LAN-only`, `no` requires a leak note) and **E-01 Exposure entry.narrowing**; keep the contract in `contracts/exposure-contract.md` authoritative for the row set
- [X] T015 [P] [US1] Replace the README "External Ports" section with a link to `docs/exposure.md` plus the one-line rule that a new port needs a row (README lines ~44-58)
- [X] T016 [US1] Add `explorer` to the `networks:` block of `docker-compose.private.yml` if `api`/`web` need it when stacked, and confirm the private overlay still starts
- [X] T017 [US1] Verify per `quickstart.md` P-1: outside scan limited to the documented set, host `ss -ltnp` shows no 8332/8333, membership matches T013, and explorer blocks still advance; record the result in `specs/002-default-security-hardening/baseline.md`

**Checkpoint**: MVP complete — the default stack is no longer over-exposed, and the same is true in every mode.

---

## Phase 4: User Story 2 - Nothing works by default because of a known password (Priority: P2)

**Goal**: Credentials are generated per deployment, warned about, and rotatable in one command
without losing explorer data.

**Independent Test**: `quickstart.md` P-2 — no credential equals `mempool`/`admin`, the old
literals fail, rotation keeps the explorer working, no value appears in logs.

- [X] T018 [US2] Rewrite `.env.example` with a documented header and empty placeholders for `MYSQL_PASSWORD`, `MYSQL_ROOT_PASSWORD` (and keep `TOR_CONTROL_PASSWORD`), per `research.md` R-06
- [X] T019 [US2] Write `scripts/generate-secrets.sh` to the `contracts/cli-contracts.md` C-01 contract: create `.env` from `.env.example` when absent, fill blank `data-model.md` **E-02 Credential.value** fields and track the `data-model.md` **E-02 Credential.generated** state with `openssl rand -hex 24`, never overwrite, mode 600, one `WARN: <VAR> generated` line per value, never print a value
- [X] T020 [US2] Replace the literal database passwords in `docker-compose.yml` and `docker-compose-testnet4.yml` with `${MYSQL_PASSWORD:?Set MYSQL_PASSWORD in .env}` and `${MYSQL_ROOT_PASSWORD:?…}`, on both the `db` service and the `api` consumer (`DATABASE_PASSWORD`)
- [X] T021 [US2] Call `scripts/generate-secrets.sh` from `install.sh` before the second-run `up`, and print the pointer to `scripts/rotate-db-password.sh`
- [X] T022 [US2] Write `scripts/rotate-db-password.sh` to contract C-02 and `data-model.md` **E-02 Credential.rotation**: `ALTER USER` in the running `db` first, then rewrite `.env`, then restart `api` and `web`; refuse when `db` is down; support `--value`
- [X] T023 [US2] Document first-run secret generation, the placeholder warnings, rotation, and that the `.env` file belongs in the backup scope (FR-023a) in the README installation section
- [X] T024 [US2] Verify per `quickstart.md` P-2, including rotating back with `--value`, and record the result

**Checkpoint**: No shipped credential is a published string; rotation is one command and keeps data.

---

## Phase 5: User Story 3 - Third-party trust is written down and posture is visible (Priority: P3)

**Goal**: Every external artefact has a recorded trust basis and refresh trigger, the snapshot
is backed by the chain's own work, images are pinned, and the hardening posture is auditable
with deviations as data.

**Independent Test**: `quickstart.md` P-3 — trust record is complete, zero `:latest`, audit
reports zero drift and flags an injected one, the snapshot hash check matches.

- [X] T025 [US3] Create `docs/trust.md` with one row per external artefact, honouring `data-model.md` **E-03 Trust record.trust basis** and **E-03 Trust record.refresh**, plus a **E-03 Trust record.risk note** wherever the basis is not signature-verified
- [X] T026 [P] [US3] Add the snapshot verification table to `docs/trust.md` per `data-model.md` **E-04 Snapshot verification record.height** (must equal the README's import height), **E-04 Snapshot verification record.check command** and `data-model.md` **E-04 Snapshot verification record.expected hash** and **E-04 Snapshot verification record.on mismatch**, plus the plain statement that a checksum only proves the transfer (FR-012a, `research.md` R-08)
- [X] T027 [US3] Replace the seven floating image references with the confirmed exact versions from T004 across all four compose files, and add an inline comment per image pointing at `docs/trust.md`
- [X] T028 [US3] Write `scripts/refresh-images.sh` to contract C-05: age report without `--pull`, deliberate `docker compose pull` with it, exit 1 on any unpinned reference
- [X] T029 [US3] Write `scripts/audit-hardening.sh` to contract C-04: render `cap_drop`, `cap_add`, `no-new-privileges`, `pids_limit`, `read_only`, `user`, `health` per service, verdict from `data-model.md` **E-05 Health verdict.verdict** vocabulary on the `data-model.md` **E-05 Health verdict.state** values, `deviated` on a T006 row, `DRIFT` otherwise, `stale-deviation` for a row with no live deviation
- [X] T030 [US3] Add `read_only: true` with the `tmpfs` mounts from `research.md` R-04 to the tolerated services in `docker-compose.yml` and `docker-compose-testnet4.yml`
- [X] T031 [US3] Pin `user:` where the image tolerates it and add a deviation row for every service that stays root or writable, per R-04 and T006
- [X] T032 [US3] Document the audit and refresh commands, the trust record, and the snapshot verification step in the README, each with its first-diagnostic use
- [X] T033 [US3] Verify per `quickstart.md` P-3, including the injected-drift and removed-deviation cases and a restore, and record the result

**Checkpoint**: Trust is stated, pins are exact, and the posture is checkable rather than remembered.

---

## Phase 6: User Story 4 - The node says when it is unhealthy (Priority: P4)

**Goal**: Every long-running service reports a functional health verdict in one command, and
logs cannot fill the card.

**Independent Test**: `quickstart.md` P-4 — all healthy on a good stack, stopping `bitcoin`
marks it and its dependents not-healthy with a non-zero exit, logs stop at the cap.

- [X] T034 [US4] Add the `healthcheck:` block to every service in all four files exactly per `contracts/health-probes.md`, using the binaries confirmed in T002 and honouring the per-service `start_period`
- [X] T035 [US4] Switch the hard dependencies to `depends_on: {condition: service_healthy}` (`electrs→bitcoin`, `api→db`, `web→db`, `bitcoind_exporter→bitcoin`) in `docker-compose.yml` and `docker-compose-testnet4.yml`
- [X] T036 [US4] Add a `healthcheck` to `tor` in `docker-compose.private.yml` (SOCKS accept) and switch `bitcoin`/`api` to `restart: on-failure` where an unhealthy-but-running container must stay visible
- [X] T037 [US4] Write `scripts/security-status.sh` to contract C-03 and `data-model.md` **E-05 Health verdict.overall`: per-service verdicts, `OVERALL:`, `--json`, non-zero exit on any unhealthy, bounded by the probe timeouts
- [X] T038 [US4] Document `scripts/security-status.sh`, what each verdict means, and a first diagnostic command per unhealthy service in the README
- [X] T039 [US4] Verify per `quickstart.md` P-4, including the `bitcoin` stop/start cycle and the log-cap inspection, and record the result

**Checkpoint**: All four stories work independently and together.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Consistency, cross-mode proof, and a rehearsed exit.

- [X] T040 Run `scripts/check-overlay-parity.sh --verbose`, `docker compose config` for all four modes, and `scripts/audit-hardening.sh`; fix every hit
- [X] T041 Cross-link `docs/exposure.md`, `docs/trust.md` and `docs/hardening-baseline.md` from the README (one task — the README is the single shared file); remove any now-duplicated text
- [X] T042 [P] Cross-link the three `docs/` files to each other, in the same pass as T041 only if different authors
- [X] T043 [P] Update `docs/network-normal.svg` and `docs/network-tor.svg` for the three-network split
- [X] T044 Run the private-mode checks (onion ID present, only onion reachable, LAN explorer still reachable) and the testnet4 pass from `quickstart.md` P-5
- [X] T045 Rehearse rollback per `quickstart.md` P-0 and confirm chain data is intact afterwards
- [X] T046 Walk `quickstart.md` end to end once and fix any step that is not copy-pasteable

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (P1)**: none — start immediately
- **Foundational (P2)**: needs Setup; blocks all stories
- **US1 (P3)**: after Foundational. **US2** after Foundational. **US3** needs T002/T004 (Setup) and is best after US1 (audit reads the live network state). **US4** needs T002 and US3's T029 for verdict wording.
- **Polish (P7)**: after all four stories

```
Setup(1) → Foundation(2) → US1(3) ─┐
                          US2(4) ─┼→ US3(5) → US4(6) → Polish(7)
```

### Story Dependencies

- **US1**: independent, delivers the MVP
- **US2**: independent of US1 (touches different keys); both touch the same compose files, so land them in order if one author
- **US3**: independent to build, but its audit reports US4's healthchecks — write `no-healthcheck` handling before T029 is meaningful, or land T029 after T034 and recheck
- **US4**: independent to build; `depends_on: condition: service_healthy` is only valid once T034 exists

### Parallel Opportunities

- Setup: T003 and T005 in parallel (different artifacts); T004 and T006 follow the file edits
- Foundation: T009 in parallel with the T007/T008 edits; T010 last (it validates both)
- US1: T015 in parallel with T014 only if the exposure table is already drafted; otherwise sequence them
- US3: T026 in parallel with T025 (different sections but the same file — split by section, or sequence)
- Polish: T043 in parallel with T041/T042 (different artifacts)

```bash
# Setup, parallel once T002 starts
Task: "Confirm read_only tolerance per R-04"        # T003
Task: "Confirm openssl/awk/curl availability"        # T005
```

## Implementation Strategy

**MVP = Phase 1-3 (US1 only)**: removes the host-exposed RPC port and the flat network,
which is the only directly exploitable default. Stop, run `quickstart.md` P-1, deploy.

**Incremental**: after the MVP, land US2 (secrets), then US3 (trust/posture), then US4
(health). Each is independently verifiable, and none of them require US1 to be reverted.

**If two authors**: US1 and US2 split cleanly by key set, but agree the compose-file order
first — both write to the same four files.

## Format validation

- 46 tasks, IDs T001–T046, sequential with no gaps.
- Every task: checkbox, ID, description, at least one exact path.
- [P] only where no other [P] task in the same phase touches the same file (verified).
- Story labels present on all 29 story tasks (US1 7, US2 7, US3 9, US4 6); none on Setup,
  Foundational or Polish.
- Every constrained `data-model.md` field is cited by at least one implementing task.

## Notes

- Every compose task names all affected files; do not fix the base alone (overlays inherit nothing).
- Commit per task or logical group, per the constitution's workflow gate.
- `[P]` tasks touch different files by construction — verify before parallelising.
- Deviations are only acceptable with a T006 row; an unexplained one is drift.
