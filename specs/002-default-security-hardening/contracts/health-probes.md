# Contract: health probes

**Feature**: [spec.md](../spec.md) | **Plan**: [plan.md](../plan.md) | Research: R-03

Per-service probe definitions. A probe MUST test the service's function, MUST be
read-only, and MUST run as the service's own user.

## Shape

```yaml
healthcheck:
  test: ["CMD", "<binary>", "<args>"]   # or ["CMD-SHELL", "... | grep ..."]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: <per-service>
```

`start_period`: `300s` for `bitcoin`, `electrs`, `api`; `120s` for the rest;
`60s` with `interval: 10s` for `tor`; `-` for `import` (one-shot) and for the
short-lived import's `bitcoin`.

## Definitions

| Service | `test` | Function proven |
| --- | --- | --- |
| `bitcoin` | `bitcoin-cli getblockchaininfo` returns and contains `"initialblockdownload": false` | serving as a synced node (a syncing node is `starting`, honestly) |
| `electrs` | `wget -qO- localhost:4224/` exits 0 | index serving |
| `web` | `wget -qO- localhost:8080/` exits 0 | front end serving |
| `api` | `wget -qO- localhost:8999/api/v1/blocks` exits 0 | backend querying electrs |
| `db` | `healthcheck.sh --connect --innodb_initialized` | accepting SQL |
| `grafana` | `wget -qO- localhost:3000/api/health` contains `"database": "ok"` | serving and backended |
| `prometheus` | `wget -qO- localhost:9090/-/ready` | ready to serve queries/scrapes |
| `node_exporter` | `wget -qO- localhost:9100/metrics` exits 0 | exporting host metrics |
| `json_exporter` | `wget -qO- localhost:7979/-/healthy` exits 0 | probe endpoint up (fallback `/metrics`) |
| `bitcoind_exporter` | `wget -qO- localhost:9332/metrics` contains `bitcoin` | node metrics flowing |
| `cadvisor` | `["CMD","/usr/bin/cadvisor","-h"]` fallback, or HTTP `healthz` if a fetcher exists | container metrics serving |
| `public-pool` | `wget -qO- localhost:3334/` exits 0 | pool API serving |
| `btctrack` | `wget -qO- localhost:8501/` exits 0 | UI serving |
| `tor` | `nc -z 127.0.0.1 9050` | SOCKS proxy accepting in the shared namespace |

If the documented binary is absent from an image, the fallback is: same endpoint
via `sh -c` with `busybox` applets; if the image has no shell at all, degrade to
the process-only form and add a deviation row (FR-018) naming the lost signal.

## Dependency ordering

`depends_on` uses `condition: service_healthy` where a hard dependency exists:
`electrs→bitcoin`, `api→db`, `web→db`, `bitcoind_exporter→bitcoin`. A service
whose probe needs a dependency's health therefore orders correctly.

## Failure semantics

- A failed probe marks only that service `unhealthy`; `security-status.sh` exits
  non-zero, and the overall verdict is wrong for zero dependency failures
  (SC-004).
- `api`/`web` are left on `restart: on-failure` rather than `always`, so an
  unhealthy-but-running service is visible instead of being thrashed.

## Anti-patterns (rejected)

- `pgrep bitcoind` — passes on a wedged process.
- TCP connect only — passes on a listening-but-unbackended server.
- Probes that call a dependency (e.g. `api` curling `electrs`) — marks the wrong
  service unhealthy.
- Probes that write (e.g. a test block) — not idempotent against mainnet.
