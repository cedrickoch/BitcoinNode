# Network exposure

Every port this stack publishes to the host, with its purpose and whether anything
authenticates it. This is the canonical table: a published port without a row here
is a defect, and so is a row without a published port.

Contract: `specs/002-default-security-hardening/contracts/exposure-contract.md`.
Related: [hardening baseline](hardening-baseline.md) · [trust record](trust.md).

**Rule for adding a port:** in one commit — the compose change, a row here, the
README mention, and a re-run of `scripts/check-overlay-parity.sh` plus
`docker compose config` for every mode.

## Published ports (default mode)

| Port | Service | Purpose | Authenticated | Modes | Why it cannot be narrowed |
| --- | --- | --- | --- | --- | --- |
| `80` | web | Block explorer UI — browse blocks, transactions, mempool state | no | default, testnet4 | meant for a browser on another device; chain and mempool data are public by nature, but your node's peers, sync progress and IP exposure are visible |
| `3000` | grafana | Dashboards: node health, container resources, miner telemetry | no | default, testnet4 | read from a browser; shows host/container names, disk usage, miner serials and any wallet balance panel you add — treat a screenshot as internal |
| `3333` | public-pool | Stratum, primary — point a Bitaxe or other miner here | no | default | miners connect from their own devices; Stratum has no authentication layer |
| `3334` | public-pool | Stratum/API variant — second difficulty tier | no | default | same as above |
| `50001` | electrs | Electrum server — wallet software (Sparrow, Electrum, BlueWallet) | no | default | wallet devices connect directly; this is the whole point of running your own node |
| `8501` | btctrack | Address-tracking UI with balances | no | default | read from a browser; shows wallet balances, so it leaks more than the explorer |
| `40001` | electrs | Electrum server on testnet4 | no | testnet4 | same role as `50001` |
| `44224` | electrs | Metrics endpoint exposed directly on testnet4 | no | testnet4 | testnet4 has no Prometheus, so the metrics port is published instead |
| `9090` | prometheus | Prometheus UI and query API on testnet4 | no | testnet4 | testnet4 exposes it directly in place of the dashboard stack; shows raw metrics and the target list |

Nothing here carries authentication. Assume anyone on your LAN can open all of it.

## Not published (container-only)

| Port | Service | Reached by |
| --- | --- | --- |
| `8332` / `48332` (testnet4) | bitcoin | electrs, api, bitcoind_exporter on the `core` network; `public-pool` via the shared data volume; the Tor container via loopback in the shared namespace. Bound to `127.0.0.1` and the node's fixed core address `172.28.0.2` |
| `8333` / `48333` (testnet4) | bitcoin | P2P: electrs on `core`; inbound onion connections in private mode |
| `8080` | web | nginx inside the front-end container |
| `8999` | api | internal API server |
| `3306` | db | api on `explorer` |
| `9100` | node_exporter | prometheus |
| `7979` | json_exporter | prometheus |
| `9332` | bitcoind_exporter | prometheus |
| `8080` | cadvisor | prometheus |
| `4224` | electrs | prometheus (default mode only) |
| `9050` / `9051` | tor | bitcoind only — `network_mode: service:bitcoin` |
| `8501`-internal, `3000`-internal | grafana | same as published where applicable |

## Checking it

```sh
# from a second machine on the same LAN
nmap -Pn -p- <node-ip>
```

Expect only the table above. `scripts/security-status.sh` additionally reports any
service listening on `0.0.0.0` where the design says it should not.

## Modes that publish nothing

`docker-compose-import.yml` is one-shot and publishes no ports at all.
