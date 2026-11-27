# Contract: published ports

**Feature**: [spec.md](../spec.md) | **Plan**: [plan.md](../plan.md) | Data model: E-01

The operator-visible contract for reachability. The canonical table lives in
`docs/exposure.md`; this file defines what makes a row valid.

## Rules

1. The union of `ports:` across shipped compose files MUST equal the port set in
   `docs/exposure.md` — no publish without a row, no row without a publish
   (FR-001, FR-020).
2. No mode may introduce a port the default mode does not already publish, except
   the documented per-mode set already established by the parity feature (FR-020):
   testnet4 may substitute `40001`, `44224`, `9090`; import publishes nothing.
3. Every row declares `authenticated`: `yes`, `no`, or `same-LAN-only`. `no`
   requires a note naming what a viewer can see (FR-001a).
4. Every row is published as `<host>:<container>` with the host side bound to the
   documented interface. `0.0.0.0` is acceptable only where the row says so.
5. A port that exists only for other containers is not published at all
   (FR-002) — e.g. RPC `8332` after this feature.

## Current contract surface (post-feature)

| Port | Service | Authenticated | Note |
| --- | --- | --- | --- |
| 80 | web | no | block explorer; chain and mempool data are public by nature, but your node's peers, sync state, and IP exposure are visible |
| 3000 | grafana | no | dashboards; shows host/container names, disk, CPU, miner serials and wallet balance entries — treat screenshots as internal |
| 3333 | public-pool | no | stratum; open by design so miners can connect |
| 3334 | public-pool | no | stratum/API variant |
| 50001 | electrs | no | Electrum; open by design so wallets connect |
| 8501 | btctrack | no | wallet-balance tracker UI; shows balances |
| 9090 | prometheus | no | testnet4 mode only; raw metrics and target list |
| (testnet4) 40001 | electrs | no | Electrum on testnet4 |
| (testnet4) 44224 | electrs | no | metrics endpoint on testnet4 |

Not published (container-only): `8332` (RPC), `8080` (web internal), `8999`
(api), `3306` (db), `9100` (node_exporter), `7979` (json_exporter), `9332`
(bitcoind_exporter), `8080` (cadvisor), `4224` (electrs metrics, default mode),
`9050`/`9051` (Tor, inside the node's namespace), `8333` (P2P; onion inbound in
private mode is unaffected).

## Verification

- `docker compose config --format json` (per mode) → extract published ports →
  compare with the table; any difference fails.
- From another machine: `nmap -Pn -p- <node-ip>` shows only the table's ports.
- `scripts/security-status.sh` additionally reports any service listening on
  `0.0.0.0` inside its container where the design says it should not.

## Change procedure

Adding a port requires, in one commit: the compose change, the `docs/exposure.md`
row, the README mention, and a re-run of `scripts/check-overlay-parity.sh` plus
`docker compose config` for every mode.
