# Feature Specification: Compose Overlay Hardening & Image Parity

**Feature Branch**: `main`

**Created**: 2026-11-27

**Status**: Draft

**Input**: User description: "Bring the testnet4 and bitaxe-monitor overlays to hardening/image parity with the base compose file" (from the accepted constitution TODO, v1.1.0). Clarified: retire the miner-monitoring overlay (default mode already covers it), keep the snapshot-import and test-network overlays standalone-runnable.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Every run mode is equally hardened (Priority: P1)

An operator switches the node from mainnet to another run mode (test network trial, miner monitoring, or a fresh snapshot import). The containers that come up must be exactly as hardened as the mainnet default: no added capabilities, no lost "no new privileges", no unset process limits, no read-write root filesystem where the default is read-only.

**Why this priority**: The constitution makes the hardening baseline non-negotiable and forbids an overlay from weakening what it overrides. Today the non-default modes silently drop the whole baseline, so a trial on the test network — the very rollout the build guide recommends before mainnet — runs with the weakest posture. Fixing this is the core value of the feature.

**Independent Test**: Bring up each documented run mode and inspect its containers; every service must satisfy the same hardening checklist that the mainnet default satisfies, with any exception explained in an inline comment.

**Acceptance Scenarios**:

1. **Given** the node running in the default mode, **When** the operator switches to any other documented mode, **Then** every service that runs still satisfies the full hardening baseline.
2. **Given** any mode is running, **When** the operator inspects a service, **Then** at most the documented minimum of added capabilities is present, and each one carries a comment naming its reason.
3. **Given** a service in the default mode is read-only, **When** the same service runs under another mode, **Then** it is still read-only.

---

### User Story 2 - Every mode runs the verified image, not a legacy one (Priority: P2)

The operator brings up a non-default mode and gets the same proven, signature-verified node software as mainnet, rather than an older third-party image left behind by an earlier revision.

**Why this priority**: Supply chain integrity is non-negotiable, and mode-dependent binary drift means mainnet is verified while the trial mode is not. It also means a test-network trial does not actually rehearse the software that will run on mainnet, which defeats the purpose of the trial.

**Independent Test**: For each mode, compare the node software used against the default mode; the same verified image reference must be used, and no mode may reference a legacy third-party node image.

**Acceptance Scenarios**:

1. **Given** a mode that starts the node service, **When** its image reference is compared with the default mode, **Then** they are identical.
2. **Given** a mode is brought up, **When** the node reports its version, **Then** the version matches the default mode's pinned version.
3. **Given** the data location differs between the legacy and current node image, **When** the switch happens on an existing install, **Then** the migration or re-sync consequence is stated in the documentation.

---

### User Story 3 - Each mode is documented and reproducible (Priority: P3)

The operator can discover every supported mode, know its purpose, and bring it up and down using only the documentation, with no undocumented manual edits.

**Why this priority**: The test-network overlay is mentioned nowhere in the operator documentation, so it is effectively unfindable and untested knowledge. Documentation is a merge gate under the constitution but is worth less than the hardening and image work.

**Independent Test**: Follow only the documentation to start and stop each mode; the run succeeds and the mode's purpose and prerequisites are clear before starting.

**Acceptance Scenarios**:

1. **Given** the documentation, **When** the operator looks for available run modes, **Then** every supported mode is listed with its purpose and prerequisites.
2. **Given** a documented mode, **When** the operator follows the steps verbatim, **Then** the stack starts without manual file edits.
3. **Given** a mode is running, **When** the operator follows the documented stop and revert steps, **Then** the node returns to the default mode and stays usable.

---

### User Story 4 - The redundant miner overlay is retired without losing monitoring (Priority: P4)

An operator who previously used the miner-monitoring overlay stops being told to choose between it and the default file. Miner monitoring works in the default mode, and the retired file is gone rather than lingering as a third variant to keep in sync.

**Why this priority**: Retiring it is what shrinks the maintenance surface, but it is only safe because the default mode already carries the same scraper service and scrape job. It ranks last because it delivers cleanup rather than new capability, and it depends on the parity work above.

**Independent Test**: Bring up the default mode and confirm miner metrics still arrive as before, with no miner overlay file present and no documentation referencing it.

**Acceptance Scenarios**:

1. **Given** the miner overlay has been retired, **When** the default mode runs, **Then** the miner metrics scraper and its scrape job are still present and functioning.
2. **Given** the retired overlay is removed, **When** the operator searches the repository, **Then** no file, script, or document still references it.
3. **Given** an operator was running the retired overlay, **When** they follow the migration note, **Then** they end up on the default mode with existing data still readable.

---

### Edge Cases

- **Mode-to-mode switching with different data locations.** The legacy node image uses a different data path than the current one, so switching brings up a node that finds no chain data. What happens, and what must the operator be told?
- **Overlays do not inherit anything.** Each overlay stands alone, so a fix applied to the default file does not reach an overlay by itself. What catches that drift before it reaches a running node?
- **The retired overlay's data path.** The retired miner overlay mounted the node data at a different path than the default file. What does an operator switching off it need to do so their existing chain data is still found?
- **Added capabilities that an overlay may no longer need.** The node service needs extra capabilities only because of how its current startup handling works. Once an overlay carries them itself, are they all still required there?
- **A snapshot import that outlives the container.** The import runs a long one-shot job and is expected to exit; what happens on restart while it is unfinished?
- **Bringing up two modes at once by mistake**, since standalone overlays each define the whole stack and both share the same data volume.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Every supported run mode MUST apply at least the full hardening baseline of the default mode to every service it starts.
- **FR-002**: An overlay MUST NOT remove a hardening property that the default mode sets, unless removal is required for the mode to function and is explained in an inline comment.
- **FR-003**: Any added capability in any mode MUST be limited to the minimum needed and MUST carry an inline comment naming the reason.
- **FR-004**: Where an overlay overrides a service, the image reference MUST match the default mode's image for that service.
- **FR-005**: No mode MUST reference a legacy or version-drifting third-party node image once the feature is complete.
- **FR-006**: Each supported mode MUST be documented with its purpose, prerequisites, start command, stop command, and revert-to-default steps.
- **FR-007**: Every documented mode MUST be startable using only documented steps, with no manual file edits.
- **FR-008**: Pre-existing helper scripts and documented commands that reference an overlay MUST remain valid, or be updated in the same change.
- **FR-009**: Every shipped overlay MUST be validated as part of the merge gate, not only the default mode.
- **FR-010**: The number of externally exposed ports MUST NOT increase as a result of this feature.
- **FR-011**: Combined use of two overlays that are not documented as compatible MUST either be prevented or documented as unsupported.
- **FR-012**: Drift between the base file and an overlay (image, hardening, or duplicated configuration) MUST be detectable by a repeatable check rather than by review alone.
- **FR-013**: The supported mode set MUST be the default mode, a snapshot-import mode, and a test-network mode; the miner-monitoring overlay MUST be retired because its only unique service and scrape job already exist in the default mode.
- **FR-014**: Each overlay MUST remain runnable on its own, without the base file, so existing scripts and documented commands keep working unchanged; consequently each overlay MUST repeat the full hardening baseline and image references rather than relying on inheritance.
- **FR-015**: Retiring an overlay MUST NOT lose capability; the default mode MUST still provide miner monitoring equivalent to what the retired overlay provided.
- **FR-016**: Removal of a retired overlay MUST include updating or removing every script, document, and reference that names it, plus a migration note for operators already using it.
- **FR-017**: Each overlay MUST be identifiable as self-sufficient, and the documentation MUST warn that overlays are alternatives, not stackable layers.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of services in every supported mode satisfy the full hardening baseline (target: zero exceptions, other than commented, minimal capability additions).
- **SC-002**: Zero image-reference mismatches between the default mode and any overlay for the same service, and zero legacy node image references.
- **SC-003**: The number of documented run configurations equals the number of shipped compose files; zero files are undocumented and zero are orphaned.
- **SC-004**: An operator who has never seen the repository can start and stop each mode in under 5 minutes using documentation alone, with zero manual file edits.
- **SC-005**: A single repeatable check reports all default-versus-overlay drift in under 1 minute, and reports none when the work is complete.
- **SC-006**: Zero increase in externally exposed ports.
- **SC-007**: No convenience regressions: every mode that works today still reaches a working state after the change, and miner metrics remain available after the retirement.
- **SC-008**: Zero remaining references to a retired overlay anywhere in the repository.

## Assumptions

- The default mode's existing hardening baseline is the reference standard; this feature aligns other modes to it and does not redesign the baseline itself.
- The node software is built and pinned by the project; the build guide already instructs switching remaining files from the legacy image to it, so parity means adopting the same reference.
- The Raspberry Pi and Docker host are available for verification; validation is manual and repeatable rather than automated in a pipeline (the project has none yet).
- The miner-monitoring overlay's scraper configuration is unchanged by retirement; only its location moves, and it already exists in the default file.
- The snapshot import remains a separate, explicitly invoked migration step and is not folded into normal startup.
- Documentation lives in the existing operator README and related in-repository docs; no new documentation site is introduced.
- Standalone overlays are accepted as duplicative by design; the drift check is the guard that makes duplication safe.
