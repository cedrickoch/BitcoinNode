# Contract: operator scripts

**Feature**: [spec.md](../spec.md) | **Plan**: [plan.md](../plan.md)

All five scripts are POSIX `sh` under `scripts/`, follow the existing
`check-overlay-parity.sh` conventions (exit codes, `set -eu`, run from the repo
root), and are safe to re-run.

**Shared exit codes**: `0` success, `1` actionable problem found, `2` usage or
environment problem. Every script supports `--help`.

**Shared output rules**: names and verdicts only — never a secret value. Every
script that can find a problem prints `path: remediation` lines and exits `1`.

---

## C-01 `scripts/generate-secrets.sh`

Creates or completes `.env` from `.env.example`, filling each blank secret with a
random value.

| Aspect | Contract |
| --- | --- |
| Args | none; `--force-missing` regenerates values that are blank |
| Reads | `.env.example`, `.env` |
| Writes | `.env` (mode 600) |
| Idempotent | Yes — an existing non-empty value is never overwritten |
| Output | `WARN: <VAR> generated; set your own with scripts/rotate-db-password.sh` per generated value; final count |
| Exit 1 | `.env` exists but is not writable, or `openssl` is missing |
| Called by | `install.sh` before the first `up`; documented as first-run step |

**Must not**: print values; touch `.env` if all secrets are present; require a
running stack.

## C-02 `scripts/rotate-db-password.sh`

Rotates one database credential in the live database and in `.env`, then restarts
the consumers.

| Aspect | Contract |
| --- | --- |
| Args | `app` (the `mempool` user) or `root`; `--value <v>` optional |
| Preconditions | `db` is running; `.env` holds the current value; stack is in the default or testnet4 mode |
| Order | `ALTER USER` in `db` → write new value to `.env` → restart `api`, `web` |
| Output | `rotated <credential>; restarted api web` (no value) |
| Exit 1 | `db` not running, current value missing, `ALTER USER` failed |
| Exit 2 | bad/absent argument |
| Guarantee | chain volume is untouched (FR-008) |

**Must not**: recreate any volume; run while `db` is stopped; leave the database
and `.env` disagreeing on success.

## C-03 `scripts/security-status.sh`

Renders per-service and overall verdicts (data model E-05).

| Aspect | Contract |
| --- | --- |
| Args | `--json` |
| Reads | `docker inspect` for the project's containers |
| Output | One line per service (`verdict  service  detail`), then `OVERALL: <verdict>` |
| Exit 0 | overall `healthy` |
| Exit 1 | any `unhealthy`, `starting`, or `no-healthcheck` on a long-running service |
| Exit 2 | Docker unreachable, or no containers found for the project |
| Bounded | Probes resolve within their declared timeouts; report completes while the stack is degraded |

**Must not**: start, stop, or recreate containers; require the stack to be healthy.

## C-04 `scripts/audit-hardening.sh`

Reports the live hardening state of every service and flags deviations from the
baseline (data model E-06).

| Aspect | Contract |
| --- | --- |
| Args | `--json`, `--strict` |
| Reads | `docker inspect`, `docs/hardening-baseline.md` deviation table |
| Output | Per service: `cap_drop`, `cap_add`, `no-new-privileges`, `pids_limit`, `read_only`, `user`, `health`; verdict `ok` / `deviated` / `DRIFT` / `stale-deviation` |
| Exit 0 | no `DRIFT`, no `stale-deviation` (unless `--strict`, which also fails on `deviated`) |
| Exit 1 | drift found |
| Exit 2 | Docker unreachable or baseline unreadable |

**Must not**: modify anything; treat an undocumented deviation as acceptable
(SC-005).

## C-05 `scripts/refresh-images.sh`

Shows image age and performs the deliberate refresh.

| Aspect | Contract |
| --- | --- |
| Args | `--pull` |
| Without `--pull` | Lists each image, its tag, and creation date; flags any reference not pinned to an exact version |
| With `--pull` | Runs `docker compose pull`, then reports which images actually changed |
| Output | `changed <service>` per updated image, then the reminder to run `security-status.sh` |
| Exit 0 | no changes or successful deliberate refresh |
| Exit 1 | unpinned reference found, or pull failure |
| Precondition (documented, not enforced) | node is not mid-sync; a mid-sync refresh is safe but re-downloads |

**Must not**: recreate containers without the operator's `up -d`; pull while
`--dry-run`-style reporting is requested.
