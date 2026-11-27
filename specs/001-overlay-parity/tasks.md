---

description: "Task list for Compose Overlay Hardening & Image Parity"
---

# Tasks: Compose Overlay Hardening & Image Parity

**Input**: Design documents from `/specs/001-overlay-parity/`

**Prerequisites**: plan.md (required), spec.md (required for user stories)

**Tests**: Not requested as separate artifacts (no CI in this project); each story
carries its own concrete verification steps instead.

**Organization**: Tasks are grouped by user story to enable independent
implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Flat repository layout: compose files at root, new artifacts under `docs/` and
`scripts/`. See plan.md "Project Structure".

## Reference facts (measured, do not re-derive)

- `docker-compose.yml` carries 45 hardening keys across its services; it is the
  canonical baseline. It runs `4324363/bitcoind:32.1` and `4324363/electrs:v0.12.0-arm64`.
- `docker-compose-testnet4.yml` carries only 4 hardening keys (all `user:`), zero
  `cap_drop`/`security_opt`/`pids_limit`/`read_only`; it runs `bitcoin/bitcoin:31.0`
  and `4324363/electrs:v0.10.8-arm64`.
- `docker-compose-import.yml` carries zero hardening keys; it runs `bitcoin/bitcoin:31.0`
  and mounts `/import.sh` as its entrypoint.
- `docker-compose-with-bitaxe-monitor.yml` is referenced by no file at all; its only
  unique service is `json_exporter` plus the `bitaxe_json` scrape job, and both
  already exist in `docker-compose.yml` and `prometheus/prometheus.yml`.
- The legacy miner overlay and the `lncm` image use `/data/.bitcoin`; the current
  image uses `/home/bitcoin/.bitcoin`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Make parity a written, checkable standard before touching stacks

- [X] T001 Create `docs/hardening-baseline.md` stating each required per-service key from plan.md D-01 (`cap_drop: [ALL]`, minimal commented `cap_add`, `security_opt: ["no-new-privileges:true"]`, `pids_limit`, `read_only` where tolerated, rootless `user:` unless a documented entrypoint needs root) and the rule that overlays are standalone and therefore must repeat it
- [X] T002 [P] Document in `docs/hardening-baseline.md` the allowed per-mode deviations from plan.md D-02: image references, ports, and `command` may differ; every other listed key must match the baseline

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The drift checker required by FR-012 that every later phase is validated against

**⚠️ CRITICAL**: No story work can be verified until the checker exists

- [X] T003 Create `scripts/check-overlay-parity.sh` (POSIX sh, `set -eu`, executable) that parses each overlay's services and compares `cap_drop`, `cap_add`, `security_opt`, `pids_limit`, `read_only`, `user`, and `image` against the same service in `docker-compose.yml`, skipping services absent from the base
- [X] T004 Add mode-exclusion to `scripts/check-overlay-parity.sh` per plan.md D-02: `ports` and `command` are compared for presence only, never for equality, so per-mode ports and commands do not report as drift
- [X] T005 Add reporting to `scripts/check-overlay-parity.sh`: one line per drift as `<file> <service> <key> <base> != <overlay>`, an `OK` line when clean, and a non-zero exit when any drift exists
- [X] T006 Add a `--verbose` flag to `scripts/check-overlay-parity.sh` that also prints matched keys, so a reviewer can confirm the checker is not silently comparing nothing
- [X] T007 Run `scripts/check-overlay-parity.sh` and record the baseline failure output; it MUST report drift on both live overlays and MUST NOT report drift for `docker-compose.private.yml` (already hardened), proving the checker works before it is used as a gate

**Checkpoint**: Checker exists, is proven to detect real drift, and is proven not to false-positive on an already-hardened file

---

## Phase 3: User Story 1 - Every run mode is equally hardened (Priority: P1) 🎯 MVP

**Goal**: No overlay strips the hardening baseline from any service it starts

**Independent Test**: Run `scripts/check-overlay-parity.sh`; no hardening key mismatch is reported for any shipped overlay

### Implementation for User Story 1

- [X] T008 [US1] Add the full hardening block to every service in `docker-compose-testnet4.yml` (`cap_drop: [ALL]`, `security_opt`, `pids_limit` sized as in the base, `read_only` + `tmpfs` for `grafana`), replacing the bare `user:`-only stanzas
- [X] T009 [US1] Change `electrs` in `docker-compose-testnet4.yml` from `user: "root"` to `user: "1000:1000"` with the base's comment, per plan.md D-05
- [X] T010 [US1] Justify the retained capabilities in `docker-compose-testnet4.yml` with inline comments: `db`/`api` keep the base's `cap_add` set (documented entrypoint drops privileges), `bitcoin` keeps it only because the image's root entrypoint exists
- [X] T011 [P] [US1] Add the full hardening block to the `bitcoin` service in `docker-compose-import.yml`, per plan.md D-06 (no `cap_add` needed; the import entrypoint runs as the image user)
- [X] T012 [US1] Add `read_only: true` where the base has it and the service tolerates it in `docker-compose-testnet4.yml` (`grafana`), plus `tmpfs: [/tmp]`
- [X] T013 [US1] Verify per mode that hardening survives at runtime: `docker compose -f docker-compose-testnet4.yml up -d`, then `docker inspect` each container confirming `CapDrop` contains `ALL` and `no-new-privileges` is set; repeat for `docker-compose-import.yml`
- [X] T014 [US1] Confirm in `docker-compose-testnet4.yml` and `docker-compose-import.yml` that no service gained a capability the base does not grant, and that all four SC-001 exceptions are commented

**Checkpoint**: Both remaining overlays satisfy the baseline; the checker reports zero hardening drift

---

## Phase 4: User Story 2 - Every mode runs the verified image (Priority: P2)

**Goal**: No mode runs a legacy third-party node image or a drifting electrs tag

**Independent Test**: Grep both overlays for node image references and compare against `docker-compose.yml`; every mode must use `4324363/bitcoind:32.1`

### Implementation for User Story 2

- [X] T015 [US2] Replace `bitcoin/bitcoin:31.0` with `4324363/bitcoind:32.1` in `docker-compose-testnet4.yml` (FR-004, FR-005)
- [X] T016 [P] [US2] Replace `bitcoin/bitcoin:31.0` with `4324363/bitcoind:32.1` in `docker-compose-import.yml`
- [X] T017 [US2] Bump `electrs` in `docker-compose-testnet4.yml` from `v0.10.8-arm64` to `v0.12.0-arm64` to match the base
- [X] T018 [US2] Remove the now-obsolete `UID`/`GID` environment entries in `docker-compose-testnet4.yml` and `docker-compose-import.yml`, since the image runs as uid 1000 and the base no longer sets them
- [X] T019 [US2] Verify the test network mode still syncs and indexes after the swap: `docker compose -f docker-compose-testnet4.yml up -d`, confirm `bitcoind` reports 32.1 and electrs reaches its height, then tear down
- [X] T020 [US2] Verify the import overlay still runs after the swap: `docker compose -f docker-compose-import.yml up` and confirm the entrypoint reaches the header-wait loop rather than exiting
- [X] T021 [US2] Confirm the data path in both overlays is `/home/bitcoin/.bitcoin`, matching the new image, per plan.md D-04

**Checkpoint**: Both overlays use the verified, pinned image and the same data path

---

## Phase 5: User Story 3 - Each mode is documented and reproducible (Priority: P3)

**Goal**: Every mode is discoverable and startable from documentation alone

**Independent Test**: Start and stop each mode following only the README, with no manual edits

### Implementation for User Story 3

- [X] T022 [US3] Add a "Run modes" section to `README.md` listing the default mode, the private/Tor mode, the test-network mode, and the snapshot-import mode, each with purpose and prerequisites (FR-006)
- [X] T023 [US3] Add the literal start, stop, and revert-to-default commands for each mode to `README.md` (FR-007)
- [X] T024 [US3] Warn in `README.md` and `docs/hardening-baseline.md` that overlays are self-sufficient alternatives and are not stacked on the default file (FR-017)
- [X] T025 [US3] Reconcile the README import step and `README.md` line ~95 with `install.sh`, which uses `docker-compose` while the rest of the docs use `docker compose`; pick one and make both match (FR-008)
- [X] T026 [US3] Document the `bitcoin_data` volume consequence of switching modes in `README.md`: test-network data and mainnet data share one volume, so switching modes re-syncs rather than merging
- [X] T027 [US3] Verify the walkthrough by following only `README.md` for the test-network mode, confirming zero manual file edits were needed (SC-004)
- [X] T028 [US3] Confirm the external port table in `README.md` still matches the stack and that no port was added (SC-006)

**Checkpoint**: Every mode is documented, correct, and walkable without edits

---

## Phase 6: User Story 4 - Retire the redundant miner overlay (Priority: P4)

**Goal**: Miner monitoring keeps working from the default mode with no orphaned file

**Independent Test**: Grep the repository for the overlay name; no reference remains, and miner metrics still arrive in the default mode

### Implementation for User Story 4

- [X] T029 [US4] Confirm before deleting that `json_exporter` and the `bitaxe_json` scrape job are present in `docker-compose.yml` and `prometheus/prometheus.yml` (FR-015)
- [X] T030 [US4] Delete `docker-compose-with-bitaxe-monitor.yml`
- [X] T031 [US4] Add a migration note to `README.md` for operators leaving the retired overlay: switch to the default mode and, because the retired file used `/data/.bitcoin`, re-point or re-sync the volume per plan.md D-04
- [X] T032 [US4] Add the retired overlay to the checker's ignore list in `scripts/check-overlay-parity.sh` so its absence is not an error
- [X] T033 [US4] Verify miner metrics still arrive in the default mode by confirming the `bitaxe_json` target drops out of `docker-compose.yml` and `prometheus/prometheus.yml` with a non-zero scrape, then grep all repository files for the overlay name and confirm zero hits (SC-008)

**Checkpoint**: One fewer mode to maintain; miner monitoring unaffected

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Close the loop that opened this feature

- [X] T034 [P] Run `scripts/check-overlay-parity.sh` across all remaining overlays and confirm a clean `OK` exit with no drift (SC-005, FR-009)
- [X] T035 [P] Validate every shipped compose file parses: `docker compose -f <file> config` for `docker-compose.yml`, `docker-compose.private.yml`, `docker-compose-testnet4.yml`, `docker-compose-import.yml`
- [X] T036 Clear the completed `TODO(OVERLAY_PARITY)` block from `.specify/memory/constitution.md` and bump its version by PATCH with a Sync Impact Report
- [X] T037 Review the full diff across `docker-compose.yml`, both remaining overlay files, and `README.md` for accidentally exposed ports, dropped volume names, and stray `latest`-only additions
- [X] T038 Confirm SC-007 against `docker-compose.yml`, `docker-compose-testnet4.yml`, `docker-compose-import.yml`, and `docker-compose.private.yml`: every mode that worked before still reaches a working state, and note any mode deliberately left un-verified with its reason

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies
- **Foundational (Phase 2)**: Depends on Phase 1 (the baseline defines what the checker asserts)
- **User Stories (Phases 3-6)**: All depend on Phase 2
- **Polish (Phase 7)**: Depends on all stories

### User Story Dependencies

- **US1 (P1)**: Independent after Phase 2; edits hardening blocks only
- **US2 (P2)**: Independent after Phase 2 in the sense of testable alone, but shares the `bitcoin`/`electrs` service blocks with US1 in `docker-compose-testnet4.yml`, so it is easiest applied after US1 to avoid conflicting hunks
- **US3 (P3)**: Documentation only; must run after US1/US2/US4 so the docs describe the final state
- **US4 (P4)**: Must run after US2 (the retirement note depends on the settled image and data path), and before US3 completes

### Within Each User Story

- Baseline and checker before any overlay edit
- Hardening (US1) before image swap (US2) within the same file, to keep hunks separable
- Verify each mode before moving on; a mode is not done until it starts and its containers inspect clean

### Parallel Opportunities

- T001 and T002 are sequential within one file
- T011 (`docker-compose-import.yml`) can run parallel to T008-T010 (`docker-compose-testnet4.yml`) — different files
- T015 and T016 are parallel — different files
- T034 and T035 are parallel — checker versus parse validation
- Story phases can be staffed in parallel once Phase 2 lands, subject to the file overlap above

---

## Parallel Example: User Story 1

```sh
# Two agents, no file overlap:
# Agent A: docker-compose-testnet4.yml -> T008, T009, T010, T012
# Agent B: docker-compose-import.yml   -> T011
# Then T013/T014 verify both together.
```

## Parallel Example: User Story 2

```sh
# T015 and T016 touch different files and can run concurrently.
```

## Implementation Strategy

**MVP (US1 only)**: The P1 story alone closes the constitution violation — no mode
runs weaker than mainnet. Phase 1 + Phase 2 + Phase 3 is a shippable increment.

**Incremental delivery**: Ship US1, then US2 (supply chain), then US4 (retirement),
then US3 (docs catch up to the finished state). US3 last is deliberate: documenting
before the retirement would immediately need rewriting.

**Verification gate**: No phase is complete while `scripts/check-overlay-parity.sh`
reports drift, and no phase is complete with an unparsed compose file.

---

## Phase 8: Convergence

**Purpose**: Close gaps found between the shipped state and the spec/plan after the
first implement pass. Appended by `/speckit.converge`; nothing above was rewritten.

- [ ] T039 [US2] Pin the four floating monitoring images in `docker-compose-testnet4.yml` to the base references: `grafana/grafana:latest`, `prom/prometheus:latest`, `prom/node-exporter:latest`, `gcr.io/cadvisor/cadvisor:latest` are today unversioned while the base pins the explorer images; align them per FR-004 and SC-002 (partial)
- [ ] T040 [US1] Add `ports` and `command` presence comparison to `scripts/check-overlay-parity.sh` per plan.md D-02 and FR-009: a service missing a `command` or dropping a base port must report drift, matching the promise already made in `docs/hardening-baseline.md` (partial)
- [ ] T041 [US1] Copy `ulimits.nofile` (soft/hard 65536) and `ELECTRS_PARALLELISM=1` into the `electrs` service in `docker-compose-testnet4.yml` from `docker-compose.yml` so the overlay cannot fd-starve indexing per FR-001 and Constitution IV (partial)
- [ ] T042 [US4] Verify the `bitaxe_json` scrape wiring end to end in `docker-compose.yml` and `prometheus/prometheus.yml` after the retirement: confirm the `json_exporter` service and its job still produce metrics under the `pids_limit: 50` in the base file, and restore `MEMPOOL_POLL_RATE_MS` on `api` if the retired overlay's value was load-bearing per FR-015 and SC-007 (partial)
- [ ] T043 [US3] Add the missing `8501` (btctrack) row to the external-port table in `README.md` so the table remains the exhaustive authority Constitution IV requires per FR-010 and SC-006 (contradicts)
- [ ] T044 [US3] Document the `btctrack` service in the `README.md` architecture service list: it ships in `docker-compose.yml` at `:226-249` but appears in no mode documentation per FR-013 and Constitution I (partial)
- [ ] T045 [US1] Run the five runtime verifications that were ticked without Docker available: `docker compose -f docker-compose.yml config`, `-f docker-compose.private.yml config`, `-f docker-compose-testnet4.yml config`, `-f docker-compose-import.yml config`, then `up -d` plus `docker inspect` on testnet4 confirming `CapDrop=[ALL]` and `no-new-privileges`, and `docker compose -f docker-compose-import.yml up` reaching the header-wait loop per T013, T019, T020, SC-004 and SC-007 (partial)
- [ ] T046 [US4] Add an explicit retired-overlay exclusion list to `scripts/check-overlay-parity.sh` so `docker-compose-with-bitaxe-monitor.yml` stays out of the gate even if a copy is restored on disk, per T032 (partial)
- [ ] T047 [US1] Remove the dead `verbose_keys` function at `scripts/check-overlay-parity.sh:115`, or wire it into the verbose reporting path, per T006 (partial)
