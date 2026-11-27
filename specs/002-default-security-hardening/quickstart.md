# Quickstart: validating Default Stack Security Hardening

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

Runnable validation for each user story on the device. Ordered so a failure stops
before the next step depends on it. Every step is manual and repeatable; the
project has no pipeline.

**Prerequisites**: Raspberry Pi with a working default-mode stack from before this
feature, a second machine on the same LAN for outside-in checks, `nmap` on that
machine, shell access to the Pi, and the branch checked out with
`docker compose` available.

**Baseline capture before starting** (proves the rollback in P-0):

```sh
docker compose config > /tmp/before.yml
git rev-parse HEAD > /tmp/before.sha
```

---

## P-0 Rollback and fresh-install safety

1. Empty `.env`, run `scripts/generate-secrets.sh`, then `docker compose up -d`.
   → Stack reaches healthy; `.env` now has values; one `WARN` per generated value.
2. `docker compose down`, restore the previous `.env`, `git revert` the phase,
   `docker compose up -d`.
   → Stack starts, explorer renders, chain data intact (`getblockchaininfo`
   height does not reset).

## P-1 Exposure (User Story 1)

1. `docker compose up -d`, wait for all healthy.
2. From the second machine: `nmap -Pn -p- <node-ip>`.
   → Only the ports in `docs/exposure.md` answer (80, 3000, 3333, 3334, 50001,
   8501).
3. `ss -ltnp | grep -E '8332|8333'` on the Pi.
   → Neither is host-listening.
4. `docker inspect -f '{{json .NetworkSettings.Networks}}'` for `db`,
   `grafana`, `node_exporter`, `json_exporter`, `cadvisor`.
   → None lists `core`; `db` lists `explorer` only.
5. `docker compose exec db sh -c 'wget -qO- bitcoin:8332 || nc -z bitcoin 8332 || echo BLOCKED'`.
   → Fails or reports blocked.
6. `docker compose exec api wget -qO- bitcoin:8332 | head -1` and
   `docker compose exec electrs ...` → respond.
7. Open the explorer and Grafana in a browser → both render, blocks advance.

## P-2 Secrets (User Story 2)

1. `git grep -n 'MYSQL_PASSWORD\|MYSQL_ROOT_PASSWORD' docker-compose.yml` → all
   references are `${...:?…}`.
2. `docker compose exec db mysql -umempool -p"$(grep ^MYSQL_PASSWORD .env | cut -d= -f2)" mempool -e 'select 1'`
   → succeeds; repeat with `admin`/`mempool` as literals → fails.
3. `grep -c . .env`; confirm no value equals `mempool` or `admin`.
4. `scripts/rotate-db-password.sh app`; then reload the explorer.
   → Explorer still renders blocks; `api` healthy; `.env` value differs from step 2.
5. Rotate back with `--value <old>`; confirm still healthy.
6. `docker compose logs api db | grep -i 'password='`
   → no value in clear text (cookie auth means no URL secret).

## P-3 Trust and posture (User Story 3)

1. Read `docs/trust.md` alone; list every download and its basis → complete, with
   no entry lacking a refresh trigger.
2. `docker compose config --images | grep -c latest` → `0`.
3. `scripts/refresh-images.sh` → lists ages, flags nothing unpinned, exit 0.
4. `scripts/audit-hardening.sh` on the untouched stack → `ok`/`deviated` only,
   zero `DRIFT`, exit 0.
5. Remove `read_only: true` from `web` in `docker-compose.yml`, re-run the audit
   → `DRIFT web read_only`, exit 1. Restore.
6. Remove `read_only: true` from `db` (which has a deviation row) → `deviated`,
   exit 0. Restore.
7. After an import, run the snapshot check from `docs/trust.md`
   → hash matches the recorded value.

## P-4 Health and logs (User Story 4)

1. `scripts/security-status.sh` on the healthy stack → all `healthy`,
   `OVERALL: healthy`, exit 0.
2. `docker compose stop bitcoin`, rerun → `bitcoin` and `electrs`, `api`,
   `bitcoind_exporter` not healthy; `OVERALL` not healthy; exit 1.
3. Start `bitcoin` again → all recover; `web`/`grafana` still served throughout.
4. `docker inspect -f '{{json .HostConfig.LogConfig}}' web`
   → `max-size 10m`, `max-file 3`.
5. Force a chatty service for a few minutes, `docker inspect -f '{{.Size}}'` on
   its log path, confirm the log stops growing at the cap.

## P-5 Cross-mode and private mode

1. `scripts/check-compose-syntax.sh` → `OK`; `scripts/check-overlay-parity.sh --verbose` → `OK`, zero drift.
2. `docker compose -f docker-compose-testnet4.yml up -d` → healthy; 40001/44224/
   9090 answer, RPC still unpublished; `scripts/security-status.sh` shows
   `no-healthcheck` only where the deviation row allows it.
3. `docker compose -f docker-compose-testnet4.yml down`.
4. Private mode: `docker compose -f docker-compose.yml -f docker-compose.private.yml up -d`
   → `docker logs bitcoind | grep -i 'Got tor service ID'` succeeds;
   `getnetworkinfo` shows only onion reachable; explorer still reachable on the LAN.
5. `docker compose down`, `docker compose up -d` back to default.

## Definition of done for the run

Every arrow above holds, `scripts/check-compose-syntax.sh` and
`scripts/check-overlay-parity.sh` are clean,
`docker compose config` parses for all four files, and the README steps used here
are the ones actually shipped (copy-paste, no hand edits).
