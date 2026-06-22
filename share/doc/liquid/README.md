# Liquid Network Documentation

This directory contains documentation for the Liquid Network integration (FEAT-305).

## Overview

Liquid is a federated Bitcoin sidechain providing:
- Confidential transactions (blinded amounts and addresses)
- Issued assets (stablecoins, securities, NFTs)
- 1-minute block times
- Two-way peg with Bitcoin

## Installation

### macOS (Homebrew)

```bash
brew install elements
```

### macOS (MacPorts)

```bash
sudo port install elements
```

### Linux (Debian/Ubuntu)

```bash
sudo apt-add-repository ppa:elementsproject/elements
sudo apt update
sudo apt install elements
```

### From Source

```bash
git clone https://github.com/elementsproject/elements
cd elements
./autogen.sh
./configure
make
sudo make install
```

## Quick Start

```bash
# Check node status
liquid daemon status

# Enable system-mode (macOS launchd / Linux systemd)
liquid daemon enable --system

# Start the node
liquid daemon start

# Monitor logs
liquid daemon monitor -f

# Create a wallet
liquid wallet new mywallet

# Get balance
liquid wallet balance mywallet

# Generate address
liquid wallet address mywallet
```

## Two-Way Peg

### Peg-In (BTC → L-BTC)

```bash
# 1. Get peg-in address from federation
liquid peg in

# 2. Send BTC to that address (via your Bitcoin wallet)

# 3. Wait for ~102 confirmations (~17 hours)

# 4. Claim your L-BTC
liquid peg claim <btc-txid>
```

### Peg-Out (L-BTC → BTC)

```bash
# Convert L-BTC back to BTC
liquid peg out bc1q... 1000000

# Check status
liquid peg status <pegout-id>
```

## Configuration

```bash
# Show current config
liquid config show

# Set network
liquid config set network liquidtest

# Set RPC user
liquid config set rpcuser myuser
```

## Networks

- `liquid` - Main network (L-BTC)
- `liquidtest` - Test network
- `regtest` - Local regression test network

## Files

- Config: `$HOME/.elements/elements.conf` (user) or `/etc/liquid/elements.conf` (system)
- Data: `$HOME/.elements/` (user) or `/var/lib/liquid/` (system)
- RPC socket: `$HOME/.elements/liquid/elements-rpc` (user) or `/var/lib/liquid/liquid/elements-rpc` (system)

## See Also

- [Elements Project](https://elementsproject.org/)
- [Liquid Network](https://liquid.net/)
- [Elements Codebase](https://github.com/elementsproject/elements)