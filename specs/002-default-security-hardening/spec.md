# Feature Specification: Default Stack Security Hardening

**Feature Branch**: `main`

**Created**: 2026-11-27

**Status**: Draft

**Input**: User description: "Harden the security of default functionality". Context: the overlay-parity feature (`specs/001-overlay-parity`) made every run mode as hardened as the default mode and made that parity checkable. What remains is the default mode itself, which is the reference for all others and has never had a hardening work item of its own. This feature closes the operator-facing gaps there: exposed surfaces, secrets, unstated trust in images and snapshot data, and the absence of any standing way to see the node's security state.

Measured starting point (default mode, 2026-11-27): 15 long-running services; 12 of them are reachable over a port from somewhere; only one service runs with a read-only root filesystem; only four pin a non-root user; the node's RPC port is bound inside the container on all interfaces on a single flat network shared by every service; the database's root password is the literal word `admin` and the explorer's database password is the service name `mempool`, both checked in; seven services track a floating tag; nothing bounds log growth; the only health signal the project has is "the container is not exited".

## Clarifications

### Session 2026-11-27

- Q: How should database credentials be provided on a first run — generated automatically for the operator, or left for the operator to paste in before the stack may start? (FR-005, FR-006) → A: The stack generates random credentials when none are supplied, uses them for that deployment, and warns loudly which values are still placeholders.
- Q: Should this feature put credentials in front of the browser dashboards, or is documenting them as unauthenticated enough? (FR-001, FR-005) → A: Document only. Dashboards stay unauthenticated by default and the exposure table records that they carry no authentication.
- Q: What must the operator do to trust the data the snapshot loads, given the download itself carries no integrity proof? (FR-012, SC-009) → A: A documented post-import check that the node, after catching up to the snapshot height, reports the expected hash for that height, so the loaded chain is backed by the network's own work.
- Q: When the operator replaces an auto-generated database password on a database volume that has already been initialised, what should the documented path be? (FR-008, FR-023) → A: One documented command rotates the password in the running database and in the environment file together, so both stay in step and the explorer data is kept.
- Q: If the node's control network is separated and a service that needs it is accidentally left off, how should that surface to the operator? (FR-002, FR-014) → A: Nothing special. The service fails to start and the operator reads its log.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Only the intended things are reachable, and only by the intended callers (Priority: P1)

An operator looks at their node from the outside and from one container to another. From the local network they reach exactly the browser pages a person uses, on exactly the documented ports. From inside, a service reaches the node's control interface only if that service has a reason to.

**Why this priority**: Reachability is the exposure that actually matters. Everything else on this list either protects a surface (secrets, network separation) or observes it (health, scans), so with the surfaces wrong the rest defends the wrong thing. It is also the only story where a default-configuration mistake is directly exploitable from the home network.

**Independent Test**: From a second machine on the same network, probe every host port of the default mode and confirm only the documented browser ports answer. From inside the stack, confirm a service with no reason to use the node's control interface cannot reach it while the services that need it still can.

**Acceptance Scenarios**:

1. **Given** the default mode is up, **When** the operator scans the node from another machine, **Then** only the documented browser ports answer, and every other documented port is either closed or reachable only from the node itself.
2. **Given** the default mode is up, **When** the operator inspects a service's listening sockets from the host, **Then** no service is listening on all interfaces unless a container on the network needs to reach it.
3. **Given** the explorer, the miner pool, and the metrics collector are running, **When** they use the node's control interface, **Then** they still succeed, because only those services are on the network that carries it.
4. **Given** the node is running in the default mode, **When** the operator opens the explorer and the dashboard from the local network, **Then** both still work.

---

### User Story 2 - Nothing works by default because of a known password (Priority: P2)

An operator configures the stack from the sample environment file. The database credentials that end up in use are the operator's, not a value that is published in the repository, and the operator is warned when a value is still a placeholder.

**Why this priority**: The database sits on the same flat network as the explorer and its password is literally `mempool` with root as `admin`. Controlled access to that database is standing access to cached chain analysis, and a shared default means a copy-pasted deployment has the same credentials as every other copy. It ranks below reachability only because the database is not published to the network at all.

**Independent Test**: Start the default mode using only the documented first-run steps; inspect the running credentials and confirm none of them equals a value that is written in the repository; also deliberately leave the environment file untouched and confirm the successful start still happens with a visible warning.

**Acceptance Scenarios**:

1. **Given** a fresh checkout, **When** the operator follows the first-run steps, **Then** the credentials in use are generated for that deployment and are not the repository's sample values.
2. **Given** the environment file still holds sample values or is empty of secrets, **When** the stack starts, **Then** it starts successfully and reports which values are placeholders, so the operator learns of them from the start message rather than from a later audit.
3. **Given** the credentials have been set, **When** existing chain and explorer data volumes are reused, **Then** the explorer keeps working without a re-sync of chain data.
4. **Given** a started stack, **When** the operator reads any page, log, or screenshot shared with a third party, **Then** no secret appears in clear text in it.

---

### User Story 3 - The trust the stack places in third parties is written down and periodically checked (Priority: P3)

The operator can find, in one place, what the stack downloads, what each download is trusted on, and what "refresh" means for each. They also have a way to see the hardening state of the running stack on demand, instead of only at review time.

**Why this priority**: The node's own software is already verified at build time; nothing else is, and the snapshot the fast-install path loads becomes the chain data the operator then trusts. Writing the trust model down makes the weaker links visible instead of implied, and a repeatable view of the hardening state keeps it from drifting back. It ranks last because it changes no behaviour on its own.

**Independent Test**: Read the deployment documentation alone and produce the full list of external downloads with the basis on which each is trusted, then run the hardening view and confirm it reports the state of every service without hand-written commands.

**Acceptance Scenarios**:

1. **Given** only the documentation, **When** the operator asks what the stack fetches from outside the repository, **Then** every such download is listed with its trust basis and its refresh trigger.
2. **Given** the bootstrap snapshot has completed, **When** the operator looks for how to confirm the imported data, **Then** the documented check backs the loaded chain by the network's own work rather than by the download alone.
3. **Given** a running stack, **When** the operator invokes the hardening view, **Then** every service's process-limit, capability, privilege-escalation, filesystem, and health state is reported, and any deviation from the written baseline is flagged.
4. **Given** a service has drifted from the baseline, **When** the weekly refresh is performed, **Then** the drift is visible in its output rather than only found by a later review.

---

### User Story 4 - The node says when it is unhealthy instead of only when it has died (Priority: P4)

An operator checks the stack's state in one command and sees whether each service is actually doing its job, not just whether a process exists.

**Why this priority**: Useful but not protective: it shortens the time a silently broken node goes unnoticed. It is last because a correctly hardened and documented stack is still valuable without it.

**Independent Test**: Stop one dependency of a service and confirm the stack's state output marks the affected service unhealthy well before a person would notice a missing block explorer page.

**Acceptance Scenarios**:

1. **Given** the stack is running, **When** the operator asks for the stack's state, **Then** each service reports a health verdict and the overall result is immediately readable.
2. **Given** the node has stopped advancing, **When** the operator asks for the stack's state, **Then** the node and the services that depend on it do not report healthy.
3. **Given** a service is unhealthy, **When** the operator follows the documentation, **Then** a first diagnostic step for that service is documented.
4. **Given** the stack runs unattended for a week, **When** the operator inspects container logs, **Then** log growth is bounded by the shipped configuration.

---

### Edge Cases

- **A port that must stay open even though it looks internal.** Wallet software connects to the Electrum port directly, so tightening the node's control interface must not also close the wallet path.
- **A chart or dashboard shown to someone else.** The dashboards stay unauthenticated by default, so the documentation must say plainly what a viewer of a default view can see and read out of it before a screenshot is shared.
- **A rollback mid-hardening.** Returning to an earlier configuration must not brick a fresh install: the first start on an empty data volume happens before any generated secret exists, so the order of the first-run steps matters.
- **Restoring from a backup or moving to a new SD card.** Without the environment file a rebuild comes up with generated credentials the database has never seen, so the backup scope must state that the environment file carries the credentials; restoring the data volume alone is not enough.
- **The bootstrap snapshot arrives over a path with no integrity proof.** A checksum only proves the file was served as-is, so the documented post-import step must back the data by the network's own work instead, and must say what to do when the reported hash does not match the expected height hash.
- **Refreshing images while the node is mid-sync.** A refresh can replace a running container; what has to be true before the operator does it?
- **A hardening tightening that the node's first start legitimately needs.** Raising privilege on a fresh volume versus on an existing one are different situations; a blanket rule would either break installs or defeat itself.
- **A service that is a fork of an upstream artefact** and therefore pinned only by its builder's own tag — the operator cannot compare it to an upstream version even by hand.

## Requirements *(mandatory)*

### Functional Requirements

**Exposure**

- **FR-001**: Every port reachable from outside the node MUST appear in the operator documentation with a stated purpose and an explicit note if it carries no authentication.
- **FR-001a**: The browser dashboards MUST stay unauthenticated by default; a started stack MUST NOT depend on an operator-set dashboard credential, and the documentation MUST state what a default view exposes to anyone who can reach the port.
- **FR-002**: The node's control interface MUST be reachable only by services that genuinely need it, on a network that other services do not share.
- **FR-002a**: A service left off the control network MUST be allowed to fail its normal start with its own log message; no separate pre-flight validation of network membership is required.
- **FR-003**: Each service's listeners MUST be bound to the narrowest interface that still works, rather than to all interfaces.
- **FR-004**: Services that need no reachability from other containers MUST NOT be attached to a network that carries services that are.

**Secrets**

- **FR-005**: The stack MUST generate random credentials for every deployment secret when the operator has supplied none, and MUST use those generated values for that deployment.
- **FR-006**: The stack MUST start successfully with no operator-supplied secret at all, so first-run ordering cannot deadlock.
- **FR-007**: The stack MUST report, in its startup output, every secret that is still at its sample or auto-generated value and therefore must be changed by the operator.
- **FR-008**: Changing a credential MUST NOT require the chain data to be re-synchronised, and MUST keep the running service working.
- **FR-008a**: Credential rotation MUST be performed by one documented command that updates the running database and the operator's environment file together, so the two cannot drift apart.
- **FR-009**: Secrets MUST NOT appear in clear text in any page, log line, or startup message the operator is likely to share.

**Supply chain and data trust**

- **FR-010**: Every external artefact the stack consumes MUST be recorded with its trust basis, and with what "refresh" means for it, in one operator-visible place.
- **FR-011**: Tag-pinned artefacts MUST be refreshed by an explicit version change or a deliberate, documented refresh, never silently.
- **FR-012**: The bootstrap snapshot MUST be accompanied by a documented post-import integrity step, completed before the imported chain data is treated as trusted: after the node has caught up to the snapshot's stated height, it MUST report the expected block hash for that height, and a mismatch MUST have a documented response.
- **FR-012a**: A checksum alone MUST NOT be presented as sufficient proof for the snapshot; the documentation MUST state what the checksum does and does not prove.
- **FR-013**: The refresh procedure MUST include a way to see that the running images are older than the newest referenced versions.

**Monitoring and hardening posture**

- **FR-014**: Each long-running service MUST have a health check that reflects whether it is performing its function, not merely that its process exists.
- **FR-015**: Health state MUST be exposed in one command whose result shows both per-service verdicts and an overall verdict.
- **FR-016**: Application logs MUST be bounded per service so an unattended run cannot fill the storage medium.
- **FR-017**: There MUST be a repeatable hardening view that reports each service's process limit, capabilities, privilege-escalation flag, filesystem mode, and health, and flags every deviation from the written baseline.
- **FR-018**: Any hardening property the baseline requires that a service cannot satisfy MUST be recorded as a documented deviation rather than silently omitted.

**Operability**

- **FR-019**: Every change in this feature MUST remain documented and reproducible from the operator documentation alone, with no manual file edits.
- **FR-020**: The hardening changes MUST NOT increase the number of documented network-exposed ports.
- **FR-021**: The private (Tor) mode MUST remain functional; a hardening change that would break the node's onion reachability is not acceptable.
- **FR-022**: A fresh install MUST still reach a working node on first start, and an existing install MUST still start with its data volumes intact.
- **FR-023**: Refresh and rollback MUST each complete in a bounded procedure in one documented step; a rollback MUST restore the previous behaviour without a re-sync.
- **FR-023a**: The documented backup scope MUST name the environment file, because it carries the deployment credentials; restoring a data volume alone MUST NOT be presented as a complete restore.

### Key Entities

- **Exposure entry**: One documented network port — number, service, purpose, whether it is authenticated, and why it cannot be narrowed.
- **Credential**: A value needed for one service pair to talk to each other — name, where it is supplied, how it is generated, and the single documented command that rotates it.
- **Trust record**: One externally consumed artefact — origin, trust basis, and refresh trigger — including those with no stronger basis than a builder's own tag.
- **Health verdict**: Per-service state plus an overall state, readable in one command.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A scan from another machine on the same network finds zero answering ports that are not in the documented exposure table.
- **SC-002**: Zero credentials in a started stack equal a value that is checked into the repository.
- **SC-003**: An operator who has not read the source can list 100% of the stack's external downloads and their trust basis from the documentation alone.
- **SC-004**: 100% of long-running services report a health verdict in one command, and the overall verdict is wrong for zero dependency failures.
- **SC-005**: The hardening view flags 100% of deliberate deviations introduced for the test, and reports none for an untouched stack.
- **SC-006**: Log growth stays bounded below a documented ceiling per service over a 7-day unattended run.
- **SC-007**: Zero increase in documented network-exposed ports.
- **SC-008**: A fresh install reaches a working node, a refresh-and-rollback cycle returns to the previous configuration, and a credential rotation leaves the explorer working, each within the documented steps and without a chain re-sync.
- **SC-009**: The bootstrap snapshot path reports the imported chain as backed by network work rather than by the download alone: the documented post-import check names an expected hash and reaches an explicit verdict at the snapshot height.

## Assumptions

- The default mode's written hardening baseline stays the reference standard; this feature closes exposure and observability gaps against it rather than redesigning it.
- "Default functionality" means the default run mode of the current stack. Structural items already solved by the overlay-parity feature — image verification at build time, overlay parity, the port table — are built on, not redone.
- Packaging the monitoring and explorer images under the project's own verified pipeline is the largest single piece of work and is treated as follow-on rather than as part of this feature; the trust record records the gap in the meantime.
- The database is single-tenant per deployment, so a credential change is an operator task against the running volume, not a multi-user migration.
- Wallet and miner devices on the network connect directly, so the Electrum and stratum ports stay network-reachable.
- The node and the dashboard are trusted enough for a single-operator home network; the dashboards stay unauthenticated by default and user accounts and per-user permissions are out of scope.
- Verification stays manual and repeatable; the project has no pipeline to run it automatically.
- The operator can reach the node's shell, so health output and refresh procedures may be delivered as scripts in the repository.

## Out of Scope

- Backups and restore of chain or explorer data (noted as a dependency for credential rotation, not built here).
- Centralised log shipping or alert routing.
- Multi-user accounts on the explorer or dashboard.
- Packaging the monitoring and explorer images under the project's own verified pipeline.
