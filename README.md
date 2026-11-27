# Project Name

![License](https://img.shields.io/badge/License-MIT-blue.svg)

## Overview

This project provides an easy way to set up a minimal personal Bitcoin node on a Raspberry Pi. It focuses on simplicity and speed by offering both automatic and manual installation methods and supports fast initial blockchain synchronization using a downloadable UTXO snapshot. The node runs inside Docker containers, making it easier to manage, start, stop, and update. The repository includes clear instructions for installing dependencies, importing blockchain data, running the node, and keeping both the Raspberry Pi OS and Docker images up to date.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Features](#features)
- [Installation](#installation)

## Architecture

The node is composed of several Docker containers defined in `docker-compose.yml`. They are grouped into four functional areas.

### Core

- **bitcoin** (bitcoind) — The Bitcoin Core full node. It validates and relays blocks and transactions on the Bitcoin network. Electrs and the Mempool API both depend on it for blockchain data via RPC and cookie-based authentication. Public-pool accesses its data directory through a shared Docker volume.
- **electrs** — An Electrum server that indexes the blockchain from Bitcoin Core. It provides a lightweight query interface used by the Mempool API and can be connected to directly by wallet software (see below).

### Mempool Explorer

- **api** (mempool/backend) — The Mempool backend. It queries electrs for indexed blockchain data, Bitcoin Core for RPC calls, and the MariaDB database for cached statistics.
- **db** (mariadb) — Stores Mempool statistics and cached data. Used exclusively by the API and waited on by the web frontend at startup.
- **web** (mempool/frontend) — The Mempool web UI. It serves the block explorer frontend and proxies API requests to the backend.

### Monitoring

- **grafana** — Dashboard UI for visualizing metrics from Prometheus.
- **prometheus** — Collects and stores metrics by scraping node_exporter, json_exporter, and cadvisor.
- **node_exporter** — Exposes host-level system metrics (CPU, memory, disk, network) to Prometheus.
- **json_exporter** — Scrapes JSON APIs and converts them to Prometheus metrics. Configured to monitor Bitaxe miners (hash rate, temperature, power, voltage, shares, etc.).
- **cadvisor** — Exposes per-container resource usage metrics (CPU, memory, network) to Prometheus.

### Mining

- **public-pool** — A solo mining pool that uses the Stratum protocol. It reads blockchain data from Bitcoin Core through a shared Docker volume. Miners (such as a Bitaxe) connect to this service to submit work.

### External Ports

The following ports are exposed to the host and can be reached from other devices on your network:

| Port | Service | Purpose |
|------|---------|---------|
| **80** | web | Mempool block explorer UI. Open in a browser to explore blocks, transactions, and mempool state. |
| **3000** | grafana | Grafana dashboards. Open in a browser to view node and Bitaxe miner metrics. |
| **3333** | public-pool | Stratum mining port. Point your Bitaxe or other miner here (e.g. `stratum+tcp://<node-ip>:3333`). |
| **3334** | public-pool | Secondary Stratum port (e.g. for a different difficulty or miner group). |
| **50001** | electrs | Electrum server port. Connect your wallet software (e.g. Sparrow, BlueWallet, Electrum) to `<node-ip>:50001` to use your own node for transaction lookups and broadcasting. |

The table describes the default mode. Test network mode publishes a different
set: **40001** (electrs) and **44224** (electrs metrics) replace 50001, and
**9090** (Prometheus UI) is exposed directly. It does not publish the mining
ports 3333/3334 nor 8501, since it has no miner or analytics service. The import
mode publishes nothing, being one-shot.

### Connecting external devices

**Wallet software** — To use your own node instead of a third-party server, configure your wallet's Electrum server setting to `<node-ip>:50001`. This works with wallets like Sparrow Wallet, Electrum, and BlueWallet. Your transactions stay private because lookups never leave your network.

**Bitaxe miner** — In the Bitaxe web UI, set the Stratum URL to `<node-ip>` and the port to `3333`. This points the miner at your local public-pool instance for solo mining. Miner statistics (hash rate, temperature, power draw, shares) are automatically collected by json_exporter and visible in Grafana.

## Features

List some key features of the project.

- Install minimal personal bitcoin node
- Fast initial blockchain sync using snapshot

## Automatic Installation

1. Install Raspberry Pi OS ( https://www.raspberrypi.com/software/ )
2. Open a terminal session to the Raspberry Pi
3. Forcing PCI Express Gen 3.0 ( sudo nano /boot/firmware/config.txt and add the lines dtparam=pciex1 and dtparam=pciex1_gen=3 to the end of the file )
4. Reboot ( sudo reboot )
5. Open a terminal session to the Raspberry Pi
6. Install pre-requisites ( sudo apt-get install docker docker-compose git -y && git clone https://github.com/cedrickoch/BitcoinNode.git && cd BitcoinNode && ./install.sh )
7. Open a terminal session to the Raspberry Pi
8. Import the bitcoin snapshot ( cd BitcoinNode && ./install.sh )

## Manual Installation

Step by step instructions:

1. Install Raspberry Pi OS ( https://www.raspberrypi.com/software/ )
2. Open a terminal session to the Raspberry Pi
3. Update the OS to the latest version ( sudo apt-get update and sudo apt-get upgrade -y )
4. Install docker as described at https://docs.docker.com/engine/install/debian/
5. Install pre-requisites ( sudo apt-get install git -y )
6. Forcing PCI Express Gen 3.0 ( sudo nano /boot/firmware/config.txt and add the lines dtparam=pciex1 and dtparam=pciex1_gen=3 to the end of the file )
7. Reboot ( sudo reboot )
8. Open a terminal session to the Raspberry Pi
9. Change to the installation directory ( e.g. cd /home/bitcoin )
10. Clone the repository ( git clone https://github.com/cedrickoch/BitcoinNode.git )
11. Change to the BitcoinNode folder ( cd BitcoinNode )
12. Download the bitcoin data snapshot ( curl https://www.lopp.net/download/utxo-snapshot-height-840000.dat?ref=blog.lopp.net --output utxo-snapshot-height-840000.dat )
13. Import the bitcoin snapshot. It will take a while ( docker compose -f docker-compose-import.yml up )
14. Start the bitcoin node ( docker compose up -d )

## Run modes

The stack has one default mode and three alternative modes. Each alternative
lives in its own overlay file and is brought up **on its own** — the overlays
are not stacked on the default file, because each one already defines the whole
stack. Always run one mode at a time; two at once share the same volume names
and will reconfigure each other.

Run `scripts/check-overlay-parity.sh` after changing any compose file. It
verifies every overlay still carries the hardening baseline of the default mode
and exits non-zero on drift. See `docs/hardening-baseline.md`.

| Mode | File | Purpose |
| --- | --- | --- |
| Default | `docker-compose.yml` | Mainnet node with explorer, monitoring and solo mining. |
| Private | `docker-compose.private.yml` | Default mode (stacked) with all peer traffic routed through Tor. |
| Test network | `docker-compose-testnet4.yml` | Throwaway testnet4 node for trying changes before mainnet. |
| Snapshot import | `docker-compose-import.yml` | One-shot bootstrap that loads a UTXO snapshot into `bitcoin_data`. |

### Default mode

```sh
docker compose up -d          # start
docker compose down           # stop
```

### Test network (testnet4)

Runs the same services as the default mode against testnet4, on ports 40001 and
44224 instead of 50001. Use it to try a change without waiting for a mainnet sync.

```sh
docker compose -f docker-compose-testnet4.yml up -d    # start
docker compose -f docker-compose-testnet4.yml down     # stop
```

Testnet4 data and mainnet data share the `bitcoin_data` volume, so switching
between them re-syncs rather than merging the two chains. Expect a fresh sync
each time you switch.

### Snapshot import

One-shot mode that loads the snapshot you downloaded into `bitcoin_data` so the
first mainnet sync is short. It has no long-running services of its own and is
not left running.

```sh
docker compose -f docker-compose-import.yml up         # run the import
docker compose -f docker-compose-import.yml down       # clean up when it exits
docker compose up -d                                   # then start the node normally
```

### Coming from the old Bitaxe monitoring overlay

The former `docker-compose-with-bitaxe-monitor.yml` has been retired: miner
monitoring is part of the default mode, so nothing is lost. To migrate:

```sh
docker compose -f docker-compose-with-bitaxe-monitor.yml down   # if still up
docker compose up -d
```

The retired file stored chain data under `/data/.bitcoin`, while the current
image uses `/home/bitcoin/.bitcoin`. You can either point the mount back at
`/data/.bitcoin` in `docker-compose.yml` to keep the existing data, or re-sync
from scratch. The `bitaxe` target in `prometheus/prometheus.yml` is unchanged and
keeps being scraped by the default mode.

### Reverting to the default mode

```sh
docker compose -f docker-compose-testnet4.yml down
docker compose up -d
```

For private mode, see the next section: either comment the `COMPOSE_FILE=` line
back out in `.env` or run `docker compose -f docker-compose.yml up -d`.

## Private mode (Tor)

By default the node talks to other Bitcoin peers over the normal internet, so every peer can see your public IP address. In private mode all peer-to-peer traffic goes through Tor, so the node only talks to `.onion` peers and your IP stays hidden. Devices on your local network (wallets, Bitaxe, browser) still connect directly to `<node-ip>` exactly as before. Only the node's traffic to the Bitcoin network goes through Tor.

**Normal mode:** bitcoind connects to peers directly through your router, so every peer sees your public IP.

![Network diagram in normal mode](docs/network-normal.svg)

**Private mode:** bitcoind can only reach the internet through the tor container, which listens on 127.0.0.1 inside bitcoind's network namespace. Peers only see the node's `.onion` address.

![Network diagram in private mode (Tor)](docs/network-tor.svg)

1. Create the config file ( cp .env.example .env )
2. Set a random control password in `.env` ( e.g. TOR_CONTROL_PASSWORD=<output of openssl rand -hex 32> )
3. Start in private mode ( docker compose -f docker-compose.yml -f docker-compose.private.yml up -d )

To always start in private mode, uncomment the `COMPOSE_FILE=` line in `.env`. After that, a plain `docker compose up -d` uses Tor. To go back to normal mode, comment it out again, or run `docker compose -f docker-compose.yml up -d`. Switching modes recreates the bitcoind container.

Verify that private mode is active:

- `docker logs bitcoind | grep -i tor` shows `Got tor service ID ...` and the node's `.onion` address
- `docker exec -u bitcoin bitcoind bitcoin-cli getnetworkinfo` shows `ipv4` and `ipv6` as `"reachable": false`, and only an `.onion` address under `localaddresses`
- `docker exec -u bitcoin bitcoind bitcoin-cli getpeerinfo | grep '"network"'` lists only `onion` peers

## Stop node

1. Change to the BitcoinNode folder ( cd BitcoinNode )
2. Stop all docker containers ( docker-compose down )

## Start node

1. Change to the BitcoinNode folder ( cd BitcoinNode )
2. Start all docker containers ( docker-compose up -d )

## Update Raspberry Pi OS

1. Stop node
2. Update the package repository ( sudo apt-get update )
3. Upgrade the OS ( sudo apt-get upgrade -y )
4. Restart the Raspberry PI ( sudo reboot )
5. Login with SSH
6. Start node

## Update docker images

1. Get the latest images ( docker-compose pull )
2. Start the latest iamges ( docker-compose up -d )
