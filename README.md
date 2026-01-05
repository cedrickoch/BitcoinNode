# Project Name

![License](https://img.shields.io/badge/License-MIT-blue.svg)

## Overview

This project provides an easy way to set up a minimal personal Bitcoin node on a Raspberry Pi. It focuses on simplicity and speed by offering both automatic and manual installation methods and supports fast initial blockchain synchronization using a downloadable UTXO snapshot. The node runs inside Docker containers, making it easier to manage, start, stop, and update. The repository includes clear instructions for installing dependencies, importing blockchain data, running the node, and keeping both the Raspberry Pi OS and Docker images up to date.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Installation](#installation)

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
