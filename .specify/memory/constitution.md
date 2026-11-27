<!--
=== SYNC IMPACT REPORT ===
Version change: 1.0.0 → 1.1.0
Change type: MINOR — one principle added and existing guidance materially
expanded, driven by repo context (docker/bitcoind Dockerfile + fetch-keys.sh,
docker/tor entrypoint, compose hardening keys) that v1.0.0 did not capture.

Modified principles:
- I. Simplicity First → I. Simplicity First (reconciled: bespoke images are
  now permitted when verified, instead of being implicitly discouraged)
- IV. Security by Least Exposure → IV. Security by Least Exposure
  (expanded with mandatory container-hardening baseline)
- V. Documentation-Driven Operations → V. Documentation-Driven Operations
  (expanded: hardening and supply-chain evidence must be documented)

Added principles:
- VI. Supply Chain Integrity (NON-NEGOTIABLE)

Added sections: none (existing sections extended rather than added)

Removed sections: none

Follow-up TODOs: none.

Resolved since v1.1.0:
- TODO(OVERLAY_PARITY) cleared in v1.1.1. Both remaining overlays now carry
  the full hardening baseline and the pinned verified image; the redundant
  miner overlay was retired (miner monitoring already lives in the base file).
  `scripts/check-overlay-parity.sh` enforces the baseline from here on.
=== END SYNC IMPACT REPORT ===
-->

<!--
=== SYNC IMPACT REPORT (v1.1.1) ===
Version change: 1.1.0 → 1.1.1
Change type: PATCH — no principle changes; the deferred overlay-parity TODO is
closed and the enforcement mechanism is named.

Modified principles: none
Added sections: none
Removed sections: none

Follow-up TODOs: none
=== END SYNC IMPACT REPORT ===
-->

# BitcoinNode Constitution

## Core Principles

### I. Simplicity First
Every service in the stack MUST have a clear, user-facing purpose for a
self-hosted personal Bitcoin node; no organizational-only or speculative
services. The project MUST prefer the smallest number of well-understood,
upstream-maintained containers. A bespoke image is permitted only when the
upstream image cannot meet a requirement, and then it MUST satisfy Principle
VI. Any added complexity (extra services, custom images, helper scripts)
MUST be justified in the README or plan documentation, or it MUST be removed.
Rationale: this is a single-operator appliance; unneeded surface costs
maintenance, boot time, and attack surface on constrained hardware.

### II. Container-First Deployment
All node services MUST run as Docker containers defined declaratively in
docker-compose files; no persistent host-installed node services are allowed.
Mode variations (snapshot import, testnet4, private/Tor, Bitaxe monitoring)
MUST be compose overlay files (e.g. `docker-compose.private.yml`), never forks
of the base `docker-compose.yml`. Host-level setup that cannot live in a
container (OS packages, `/boot/firmware/config.txt` tweaks) MUST be captured
as numbered, copy-pasteable steps in the README. Rationale: containers make
start, stop, update, and rebuild reproducible on a Raspberry Pi.

### III. Privacy & Sovereignty (NON-NEGOTIABLE)
The node MUST let the operator verify transactions with their own wallets
against their own copy of the chain (via electrs); third-party servers MUST
NOT be required for lookups or broadcasting. Private (Tor) mode MUST remain
fully supported: in private mode all bitcoind peer-to-peer traffic goes
through Tor and only `.onion` peers are contacted. Wallet, explorer, and
miner traffic stays on the local network. When private mode is active, the
operator's public IP MUST NOT be exposed to Bitcoin peers (verifiable via
`getnetworkinfo` / `getpeerinfo`). Rationale: financial sovereignty and
privacy are the core reasons this node exists.

### IV. Security by Least Exposure
Only ports explicitly documented in the README's external-port table MAY be
exposed to the host/network; every external port MUST come with a stated
purpose. RPC endpoints MUST use cookie-based or secret-based authentication;
secrets MUST live in `.env` (kept gitignored) and MUST NOT be committed.
Services that do not need wide reachability MUST be bound LAN-only or
loopback by default, and inter-container communication MUST stay on the
narrowest network that works. Every service MUST carry a container-hardening
baseline: `cap_drop: [ALL]` (any `cap_add` justified by a comment), rootless
`user:` unless a documented entrypoint needs root to chown then drop
privileges, `security_opt: ["no-new-privileges:true"]`, a `pids_limit`, and
`read_only: true` plus `tmpfs` where the service tolerates it. Overlay files
MUST NOT weaken the hardening of the service they override. Findings from
security reviews (e.g. `kochpower-security-assessment.md`) MUST be resolved
or explicitly accepted in writing before related work is merged. Rationale:
the node runs on a home network with a personal domain; least exposure is the
only sustainable defence.

### V. Documentation-Driven Operations
Every user-facing change — a new or changed service, port, mode, procedure,
or troubleshooting step — MUST be reflected in the README with
copy-pasteable commands before merge. Architecture changes MUST update the
architecture section and the network diagrams in `docs/`. Documentation and
implementation MUST land in the same change; a feature without documentation
is incomplete. Hardening and supply-chain decisions that are not
self-evident (a `cap_add`, a root entrypoint, a floating image tag) MUST
carry an inline comment stating the reason. Rationale: the README is the
operator's runbook, and a one-line comment outlives the reasoning that
produced it; drift between docs and reality breaks recovery.

### VI. Supply Chain Integrity (NON-NEGOTIABLE)
Image sources MUST be pinned and verifiable; `latest` MUST NOT be the only
version control for anything the project builds or pushes. Images built by
the project MUST be produced from GPG-verified upstream source with a
fail-closed signature check: keys pinned in the repository (never fetched
from a keyserver at build time), at least two distinct maintainers, and a
build abort on a missing, revoked, or insufficiently signed key. Built
images MUST pass the hardening assertions in the build (PIE, full
RELRO/BIND_NOW, non-executable stack, stack protector) and MUST be pinned by
`BITCOIN_VERSION`-style argument plus tag, with digest pinning preferred.
Third-party images MUST use a version tag where one exists; a floating tag
MUST be refreshed deliberately with `--pull` and MUST NOT be assumed
reproducible. Published images MUST be smoke-tested before being pushed.
Rationale: a node that verifies the chain but trusts an unverified binary is
not actually self-sovereign, and a silently re-pushed tag can swap the binary
beneath a running node.

## Operational Constraints

Technology stack — changes MUST stay aligned with this list or amend it:

- Target platform: Raspberry Pi running Raspberry Pi OS, with
  `dtparam=pciex1` and `dtparam=pciex1_gen=3` documented for PCIe Gen 3
  storage.
- Orchestration: Docker Engine + docker-compose (compose v2 syntax).
- Core: Bitcoin Core (bitcoind), electrs.
- Mempool explorer: mempool backend, MariaDB, mempool frontend.
- Monitoring: Prometheus, Grafana, node_exporter, json_exporter, cadvisor.
- Mining: public-pool (Stratum) with Bitaxe metrics via json_exporter.
- Privacy: Tor overlay (`docker-compose.private.yml`) with
  `TOR_CONTROL_PASSWORD` supplied from `.env`.

Image sourcing: `bitcoind` and `electrs` are built and pushed by the project
(`4324363/*`, see `docker/bitcoind/README.md`); `tor` is built locally from
`docker/tor`. The remaining services may use upstream images (Docker Hub,
quay.io, gcr.io, ghcr.io) under Principle VI.

Initial blockchain sync MAY use a downloadable UTXO snapshot (e.g. the
lopp.net height-840000 snapshot) to shorten bootstrap; the running node MUST
remain a fully validating Bitcoin Core node afterwards, and the snapshot
height/source MUST be stated in the README before import.

Resource prudence: the Pi is resource-constrained. Services, retention
settings, and cache sizes (e.g. Prometheus storage, Mempool caching) that are
not justified by the monitoring, explorer, or mining use cases MUST NOT be
enabled by default.

## Operational Workflow & Quality Gates

Change workflow — MUST be followed for any stack change:

1. Edit compose files and configuration in the repository; never hand-edit a
   running container without capturing the change in compose.
2. Validate: `docker compose config` MUST parse cleanly, including each
   shipped overlay (import, testnet4, private), and
   `scripts/check-overlay-parity.sh` MUST report no drift.
3. Start and verify: affected containers MUST start and pass service-specific
   checks (e.g. `docker logs bitcoind | grep -i tor` and
   `bitcoin-cli getnetworkinfo` for private mode; documented ports reachable
   on `<node-ip>`).
4. Inspect hardening: `docker inspect` on changed services MUST confirm
   `CapDrop` covers all, `no-new-privileges` is set, and the service is not
   running as root without a documented reason.
5. Document: README (and `docs/` diagrams when topology changes) MUST be
   updated in the same change.
6. Commit with a message describing the operational effect of the change.

Quality gates — all MUST pass before merge:

- Compose configuration parses for every shipped mode.
- Affected services verified running with the documented commands.
- No secrets committed; `.env` remains gitignored.
- README steps remain copy-pasteable and match actual behavior.
- No new external port without a README table entry and justification.
- No weakening of `cap_drop`/`security_opt`/`pids_limit`/`read_only` without
  an inline comment stating the reason.
- No unpinned or unverified image added, and no `latest`-only service.
- Image rebuilds (`fetch-keys.sh`, `docker buildx build`, smoke test) pass
  before anything is pushed, and `MAINTAINER_KEYS` still matches the
  release's signer list.

## Governance

This constitution supersedes all other project practices; conflicts are
resolved in favor of this document. Amendments MUST be made by editing this
file with a description of the change, its rationale, and a migration plan
for any affected deployments. Versioning follows semantic versioning:
MAJOR for incompatible governance changes (principle removal or
redefinition), MINOR for new principles or materially expanded guidance,
PATCH for clarifications and wording. All pull requests and reviews MUST
verify compliance with these principles; unjustified complexity MUST be
rejected. Runtime development guidance lives in the README and `docs/`; this
document governs principles and process.

**Version**: 1.1.1 | **Ratified**: 2026-11-27 | **Last Amended**: 2026-11-27
