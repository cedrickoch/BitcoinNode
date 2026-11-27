# Trust record

Everything this stack fetches from outside the repository, what it is trusted on,
and how it is refreshed. Written down so the weak links are visible instead of
implied: three entries below rest on no more than a tag.

Read this before a refresh, and re-read it when adding a service.

Related: [hardening baseline](hardening-baseline.md) · [exposure](exposure.md).

- **Pinned** means an exact version. A change is a commit, never a silent pull.
- **Refresh** is the concrete action that moves the entry, per the constitution's
  rule that a floating tag must be refreshed deliberately.
- `scripts/refresh-images.sh` lists image age and performs the pull.

## Images

| Artefact | Origin | Trust basis | Refresh | Risk note |
| --- | --- | --- | --- | --- |
| `4324363/bitcoind:32.1` | Docker Hub, built by this project | GPG-verified upstream source with a fail-closed 2-of-N maintainer signature check, plus hardening assertions in the build | version bump in `docker/bitcoind/Dockerfile` + `MAINTAINER_KEYS` review, then rebuild and smoke test | none beyond trusting the project's own build host; digest pinning is a follow-up |
| `4324363/electrs:v0.12.0-arm64` | Docker Hub, built by this project | same build discipline as above | rebuild on version bump | arm64-only tag |
| `4324363/public-pool:v1.7-arm64` | Docker Hub, built by this project | project-built, pinned | rebuild on version bump | tag tracks an upstream release; keep it versioned |
| `4324363/btctrack:v1.4-arm64` | Docker Hub, built by this project | project-built, pinned | rebuild on version bump | as above |
| `mariadb:11.4` | Docker Hub (`library/mariadb`) | official image, exact minor version | bump the tag deliberately, re-test first start on a fresh volume | a minor bump can require a schema upgrade step |
| `grafana/grafana:11.3.1` | Docker Hub (vendor) | vendor image, exact version | bump the tag deliberately | dashboards are unauthenticated (see `docs/exposure.md`) |
| `prom/prometheus:v3.1.0` | Docker Hub (vendor) | vendor image, exact version | bump the tag deliberately | config file format can change across majors |
| `prom/node-exporter:v1.8.2` | Docker Hub (vendor) | vendor image, exact version | bump the tag deliberately | mount paths follow the host kernel |
| `quay.io/prometheuscommunity/json-exporter:v0.6.0` | quay.io | community image, exact version | bump the tag deliberately | this image sees your miner's HTTP API |
| `ghcr.io/primexz/bitcoind-exporter:v0.5.0` | ghcr.io | community image, exact version | bump the tag deliberately | reads the node cookie |
| `gcr.io/cadvisor/cadvisor:v0.49.1` | gcr.io | community image, exact version | bump the tag deliberately | mounts `/var/lib/docker`, `/sys`, `/` |
| `alpine:3` (tor base) | Docker Hub | base image, minor-pinned | `docker compose build --pull tor` | rebuilt locally, never pushed |
| `debian:bookworm-slim` (bitcoind base) | Docker Hub | base image, minor-pinned | rebuild | digest can be pinned with `--build-arg BASE=…@sha256:…` |

## Downloaded data

| Artefact | Origin | Trust basis | Refresh | Risk note |
| --- | --- | --- | --- | --- |
| `utxo-snapshot-height-840000.dat` | `https://www.lopp.net/download/…` (a well-known index of public snapshots) | **none at transfer time** — the file arrives over TLS with no signature and no published checksum. The chain's own accumulated work is the proof, checked after import (below) | re-download only when starting from scratch | a malicious snapshot that also matches the height hash is not detectable without a re-sync; consensus rules reject most bad data as the node validates forward |

The snapshot is *not* trusted because it downloaded successfully. A checksum, if
one is ever offered, only proves the bytes arrived unaltered — it says nothing
about who produced them.

## Verifying a snapshot after import

The only real proof is that the network's accumulated work agrees with the data.
After the import finishes and the node has caught up to the snapshot height, run:

```sh
docker exec -u bitcoin bitcoind bitcoin-cli getblockhash 840000
```

Expected (`docs/trust.md` is authoritative for this value):

| Height | Expected hash |
| --- | --- |
| 840000 | `0000000000000000000320283a032748cef8227873ff4872689bf23f1cda83a5` |

- **Match** → the loaded chain is backed by network work. Continue.
- **Mismatch** → treat the data as untrusted: delete the `bitcoin_data` volume and
  either re-import or let the node sync from scratch.

## Not covered here

Packaging the explorer and monitoring images under this project's own verified
pipeline is a known gap and the follow-on work to this document. Until then, those
rows rest on a vendor or community tag.
