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
4. Install pre-requisites ( sudo apt-get install docker docker-compose git -y )
5. Forcing PCI Express Gen 3.0 ( sudo nano /boot/firmware/config.txt and add the lines dtparam=pciex1 and dtparam=pciex1_gen=3 to the end of the file )
6. Reboot ( sudo reboot )
7. Open a terminal session to the Raspberry Pi
8. Change to the installation directory ( e.g. cd /home/bitcoin )
9. Clone the repository ( git clone https://github.com/cedrickoch/BitcoinNode.git )
10. Change to the BitcoinNode folder ( cd BitcoinNode )
11. Download the bitcoin data snapshot ( curl https://www.lopp.net/download/utxo-snapshot-height-840000.dat?ref=blog.lopp.net --output utxo-snapshot-height-840000.dat )
12. Import the bitcoin snapshot. It will take a while ( docker-compose -f docker-compose-import.yml up )
13. Start the bitcoin node ( docker-compose up -d )

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
