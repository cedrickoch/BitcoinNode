# Project Name

![License](https://img.shields.io/badge/License-MIT-blue.svg)

## Overview

Briefly describe the project. What does it do? Why is it useful?

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Installation](#installation)

## Features

List some key features of the project.

- Install minimal personal bitcoin node
- Fast initial blockchain sync using snapshot

## Installation

Step by step instructions:

1. Install Raspberry Pi OS
2. Open a terminal session to the Raspberry Pi
3. Update the OS to the latest version ( sudo apt-get update and sudo apt-get upgrade -y )
4. Install Docker ( sudo apt-get install docker -y )
5. Install Docker Compose ( sudo apt-get install docker-compose -y )
6. Change to the installation directory ( e.g. cd /home/bitcoin )
7. Clone the repository ( git clone https://github.com/cedrickoch/BitcoinNode.git )
8. Change to the BitcoinNode folder ( cd BitcoinNode )
9. Download the bitcoin data snapshot ( curl https://www.lopp.net/download/utxo-snapshot-height-840000.dat?ref=blog.lopp.net --output utxo-snapshot-height-840000.dat )
10. Import the bitcoin snapshot. It will take a while ( docker-compose -f docker-compose-import.yml up )
11. Start the bitcoin node ( docker-compose up -d )

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
