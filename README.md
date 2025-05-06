# Project Name

![License](https://img.shields.io/badge/License-MIT-blue.svg)

## Overview

Briefly describe the project. What does it do? Why is it useful?

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Contributing](#contributing)
- [License](#license)
- [Contact](#contact)

## Features

List some key features of the project.

- Install minimal personal bitcoin node
- Fast initial blockchain sync using snapshot

## Installation

Describe how to install the project. Provide step-by-step instructions:

1. Change to the installation directory ( e.g. cd /home/bitcoin )
2. Clone the repository ( git clone https://github.com/cedrickoch/BitcoinNode.git )
3. Change to the BitcoinNode folder ( cd BitcoinNode )
4. Download the bitcoin data snapshot ( wget https://lopp.net/download/utxo-snapshot-height-840000.dat?ref=blog.lopp.net )
5. Import the bitcoin snapshot. It will take a few minutes ( docker-compose -f docker-compose-import.yml up )
6. Start the bitcoin node ( docker-compose up )
