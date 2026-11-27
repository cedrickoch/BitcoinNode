# Implementation Plan: Compose Overlay Hardening & Image Parity

**Branch**: `main` | **Date**: 2026-11-27 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-overlay-parity/spec.md`

## Summary

Two of the three shipped compose overlays (`docker-compose-testnet4.yml`,
`docker-compose-with-bitaxe-monitor.yml`) were written before the base file was
hardened and before the node image was self-built under GPG verification. They
override the whole stack, so they silently replace the base definitions and drop
the entire hardening baseline, and they still point at legacy third-party node
images. Because overlays are standalone (spec FR-014), nothing inherits, so each
overlay must repeat the baseline itself.

Approach: define the hardening baseline once as an operator-visible reference,
add a repeatable drift checker, bring the test-network and import overlays to
full parity (hardening, capabilities, image references, pinned tags), retire the
miner overlay whose only unique service already lives in the base file, and
document every mode including start/stop/revert steps.

Measured starting point: `docker-compose.yml` carries 45 hardening keys,
`docker-compose-testnet4.yml` carries 4 (all `user:`, none of them
`cap_drop`/`security_opt`/`pids_limit`/`read_only`).

## Technical Context

**Language/Version**: YAML (Compose Specification v2), POSIX shell for the checker

**Primary Dependencies**: Docker Engine, compose v2 CLI, `docker compose config`,
`docker inspect`

**Storage**: Named Docker volumes; no data-store change. `bitcoin_data` and
friends already exist and must keep their names so chain data survives.

**Testing**: Manual, repeatable verification per mode (no CI in this project).
`docker compose config` for parse validation, `docker inspect` for hardening
assertion, `docker compose exec` for service-level checks. Tests are not a
separate requested artifact, so task phases carry verification steps rather than
test files.

**Target Platform**: Raspberry Pi / Raspberry Pi OS, arm64, Docker host

**Project Type**: Deployment/configuration repository (compose stack), not an
application codebase

**Performance Goals**: Parity checker completes in under 1 minute; no change to
node sync or scrape cadence

**Constraints**: arm64 only; no new externally exposed ports; must not require a
re-sync of mainnet chain data; overlays must stay standalone-runnable so
`install.sh` and the documented import step keep working

**Scale/Scope**: 3 compose files in, 2 out; ~9 services per file; single operator

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Status |
|-----------|------|--------|
| I. Simplicity First | Retiring an overlay reduces service count and file count | PASS |
| II. Container-First Deployment | All work stays in compose files and documented host steps | PASS |
| III. Privacy & Sovereignty | Private/Tor overlay untouched; test-network mode keeps its own port set | PASS |
| IV. Security by Least Exposure | This feature *is* the fix for the IV violation; no port additions | PASS |
| V. Documentation-Driven Operations | Every mode documented with start/stop/revert; reasons commented inline | PASS |
| VI. Supply Chain Integrity | Legacy node images replaced by the GPG-verified pinned image; tags pinned | PASS |

**Complexity tracking**: duplication between base and overlays is deliberate
(FR-014, standalone overlays). The rejected alternative — converting overlays to
thin stacked diffs — would break `install.sh` and the documented import command.
The duplication is offset by the mandatory drift checker (FR-012), which is what
makes the trade acceptable rather than merely convenient.

## Decisions

- **D-01**: The base file's hardening block is the canonical baseline; overlays
  copy it verbatim per service. No new hardening inventions, so parity is a
  mechanical comparison.
- **D-02**: The checker compares overlay services against the base for
  `cap_drop`, `cap_add`, `security_opt`, `pids_limit`, `read_only`, `user`, and
  `image`, and exits non-zero on drift. Mode-specific *ports* and *commands* are
  excluded, because those legitimately differ per mode.
- **D-03**: Mode-specific ports are preserved (`40001`, `44224` on testnet4) so
  the mode still works; SC-006 means no *additions* beyond these existing sets.
- **D-04**: The legacy data path `/data/.bitcoin` (miner overlay, and the
  `lncm` image) differs from the current `/home/bitcoin/.bitcoin`. Retirement and
  image swaps need a migration note, not a silent path change.
- **D-05**: `electrs` in testnet4 moves from `user: "root"` to `1000:1000`, matching
  the base reasoning: it only needs to read the cookie file owned by uid 1000.
- **D-06**: The import overlay keeps its `/import.sh` entrypoint override and its
  one-shot behaviour; it gains hardening (needing no `cap_add`, as our image has
  no root entrypoint) and the verified image, and stays standalone-runnable.

## Project Structure

### Documentation (this feature)

```text
specs/001-overlay-parity/
├── plan.md              # This file
├── spec.md              # Feature specification
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Generated by /speckit.tasks
```

### Source Code (repository root)

```text
docker-compose.yml                        # Canonical baseline (reference only)
docker-compose-testnet4.yml               # Bring to parity
docker-compose-import.yml                 # Bring to parity
docker-compose-with-bitaxe-monitor.yml    # Retire
docker-compose.private.yml                # Untouched (already hardened)
install.sh                                # Import invocation (keep valid)
README.md                                 # Mode docs, retirement migration note
docs/hardening-baseline.md                # New: canonical baseline reference
scripts/check-overlay-parity.sh           # New: drift checker
.specify/memory/constitution.md           # Clear TODO(OVERLAY_PARITY) when done
```

**Structure Decision**: Flat repository layout already in use; new artifacts go
in `docs/` and `scripts/` to avoid adding root-level clutter. No template layer
is modified.

## Phase Plan

- **Phase 0**: Define the baseline and the checker (research is folded into
  Decisions D-01..D-06; no separate `research.md` needed because the decisions are
  all resolved by reading the existing files).
- **Phase 1**: Data model and contracts are not separate artifacts — the
  "model" is the per-service hardening key set, captured in
  `docs/hardening-baseline.md`.
- **Phases 3-6**: One phase per user story in priority order.
- **Phase 7**: Cross-cutting polish and constitution TODO clearance.
