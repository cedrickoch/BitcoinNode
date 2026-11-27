# Phase 1 Data Model: Default Stack Security Hardening

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Research**: [research.md](./research.md)

The "data" here is deployment metadata, not an application schema: compose
declarations, the environment file, and the two reference documents the scripts
read. Each entity below names its storage location, its fields, its validation
rules (traced to the spec), and its lifecycle.

---

## E-01 Exposure entry

**Storage**: `docs/exposure.md` (one row per published port).

| Field | Rule |
| --- | --- |
| `port` | Integer, unique. Must match a `ports:` entry in a shipped compose file (FR-001) |
| `service` | Must be a service that actually publishes that port in some mode |
| `purpose` | One sentence, non-empty, written for the operator |
| `authenticated` | `yes` / `no` / `same-LAN-only`; `no` requires a note on what leaks (FR-001, FR-001a) |
| `modes` | Which shipped modes publish it (default / testnet4) |
| `narrowing` | Why it cannot be closed, or `-` if it is LAN-scoped |

**Validation**: the port set in the document equals the union of published ports
across shipped files — no entry without a publish, no publish without an entry.
Adding a port to any compose file without a row is a review failure (FR-020).

**Lifecycle**: created in this feature by converting the README table (which
already lists every port); updated whenever a publish changes; entries are never
deleted while the port exists.

## E-02 Credential

**Storage**: `.env` (gitignored), referenced from compose as `${VAR:?message}`.

| Field | Rule |
| --- | --- |
| `name` | One of `MYSQL_PASSWORD`, `MYSQL_ROOT_PASSWORD`, `TOR_CONTROL_PASSWORD` |
| `value` | Empty placeholder in `.env.example`; generated `openssl rand -hex 24` (FR-005) |
| `generated` | Boolean state — true while the value is still the generated/sample one (FR-007) |
| `consumers` | `db` + `api` (both passwords are `db`-side for the root one, `db`+`api` for the app one) |
| `rotation` | `scripts/rotate-db-password.sh`; Tor's password rotates by edit + restart of the private overlay (FR-008a) |

**Validation**: a started stack MUST have no credential equal to a committed
string (SC-002); compose `:?` fails the start when a value is blank (FR-006 keeps
this from deadlocking because the generator runs first); no script echoes a value.

**State transitions**:

```text
absent --generate-secrets.sh--> generated (warned)
generated --rotate-db-password.sh--> operator-set (no warning)
operator-set --rotate-db-password.sh--> operator-set (new value)
```

**Invariant**: the value in `.env` and the grant inside the database agree after
every rotation, because the command does both before restarting consumers (D-05).

## E-03 Trust record

**Storage**: `docs/trust.md` (one row per externally consumed artefact).

| Field | Rule |
| --- | --- |
| `artefact` | Image reference or download, exact string |
| `origin` | Registry or URL |
| `trust basis` | One of: signature-verified source build, exact version tag, published by the project, unverified-but-known-source (FR-010) |
| `refresh` | The concrete trigger: version bump commit, `refresh-images.sh`, re-import |
| `risk note` | Required when the basis is not signature-verified |

**Validation**: every image in the four compose files appears exactly once; a
`latest`/untagged reference is a validation error; a snapshot download without a
post-import verification step is a validation error (FR-012, FR-012a).

## E-04 Snapshot verification record

**Storage**: `docs/trust.md` (single table of heights).

| Field | Rule |
| --- | --- |
| `height` | The snapshot's stated height (840000) |
| `expected hash` | The published block hash at that height |
| `check command` | Copy-pasteable, read-only |
| `on mismatch` | Documented response: treat the data as untrusted, re-import or re-sync (FR-012) |

**Invariant**: the height must equal the height named in the README's import
procedure, so the two cannot silently diverge.

## E-05 Health verdict

**Storage**: computed, not stored — `scripts/security-status.sh` renders it from
`docker inspect`.

| Field | Rule |
| --- | --- |
| `service` | Every service in the running project |
| `state` | `running`/`exited` from the engine, plus `health` when declared |
| `verdict` | `healthy` / `starting` / `unhealthy` / `no-healthcheck` (FR-014, FR-015) |
| `overall` | `healthy` only if every service is `healthy` or explicitly exempt |

**Validation**: `no-healthcheck` on a long-running service is an error, and is
only allowed for the one-shot import mode. Probes time out (10 s) so a hung
service cannot stall the report.

## E-06 Deviation entry

**Storage**: `docs/hardening-baseline.md`, "Justified deviations" table, parsed by
`scripts/audit-hardening.sh`.

| Field | Rule |
| --- | --- |
| `service` | The affected service |
| `key` | The baseline key deviated from (`read_only`, `user`, `cap_add`, `healthcheck`, …) |
| `reason` | Non-empty, technical, states what breaks without it (FR-018) |

**Validation**: the audit reports `deviated` for a matched entry and `DRIFT` for
an unmatched one (SC-005). An entry whose deviation no longer exists is reported
as stale so the table cannot rot.

## E-07 Network membership

**Storage**: the `networks:` block of the default compose file.

| Field | Rule |
| --- | --- |
| `name` | `core` (172.28.0.0/24), `explorer` (172.29.0.0/24), `default` |
| `members` | Fixed per research R-02; `bitcoin` is the only static address |
| `static address` | `172.28.0.2` for `bitcoin`, so RPC binds a known interface (R-01) |

**Validation**: no service sits on `core` without an RPC/P2P reason; `db` is on
`explorer` only; the audit prints the membership matrix so a wrong move is visible
(FR-002, FR-004).

---

## Relationships

```text
Exposure entry  ──published by──>  service (in a compose file)
Credential      ──consumed by──>    db, api           (rotation updates both sides)
Trust record    ──covers──>         every image + the snapshot download
Verification    ──backs──>          the snapshot's trust record row
Health verdict  ──measured per──>   service
Deviation       ──excuses a missing baseline key on──> service
Network member  ──determines reachability of──> RPC for a service
```

The one cross-entity rule that ties them together: a service may only be on the
network that carries RPC if its "reason" is stated, may only miss a baseline key
if a deviation row exists, and may only be `no-healthcheck` if it is the one-shot
import service.
