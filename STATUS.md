# STATUS: decentral-nodes

Repository renamed from `bitcoin` to `decentral-nodes` to reflect expanded scope.

## Goal
Fix Stacks sync with pruned Bitcoin node, rename repository to `decentral-nodes`, and plan expansion for additional decentralized infrastructure tools.

## Constraints & Preferences
- All nodes should run with minimal disk footprint (pruning enabled)
- Stacks cannot sync from genesis with pruned Bitcoin - needs chainstate archive
- Repository should support multiple blockchain/decentralized tools (not just Bitcoin)
- Privacy tools preferred: JoinMarket (most decentralized), Tor, I2Pd, Whonix
- Storage tools preferred: Storj (over Filebase), IPFS, BitTorrent
- Naming: Handshake (HNS) for decentralized DNS
- All tools in single repository (monorepo approach)
- Selective routing through Tor (not all traffic forced through Tor)

## Architecture Decisions

### Tool Tiers
- **Tier 1** (Core): Bitcoin, Lightning, Fulcrum, Liquid, Monero, Stacks
- **Tier 2** (Network Privacy): Tor daemon, I2Pd daemon, IPFS daemon, BitTorrent
- **Tier 3** (Advanced): JoinMarket, Storj, Handshake, Yggdrasil, Whonix, mempool.space

### Decisions Made
| Tool | Decision | Rationale |
|------|----------|-----------|
| JoinMarket | ✓ Tier 3 | Most decentralized CoinJoin, no coordinator, market-based |
| Storj | ✓ Tier 3 | More decentralized than Filebase, better for large files |
| Handshake (HNS) | ✓ Tier 3 | Decentralized DNS root replacement |
| Yggdrasil | ✓ Tier 3 | IPv6 overlay network, later stage |
| Tor | Tier 2 | Core privacy layer, selective routing (not forced) |
| I2Pd | Tier 2 | Alternative privacy network |
| Whonix | Tier 3 | VM-based isolation (later stage) |

### Privacy Architecture
- **Selective Tor routing**: Services opt-in to Tor, not all traffic forced through Tor
- Tor/I2Pd daemons run as system services (Tier 2)
- Applications connect through Tor when needed (opt-in basis)
- JoinMarket can operate over Tor (Tier 3)

### Naming
- Repository: `decentral-nodes`
- rpk package identity: `decentral-nodes`
- Commands use `-node` suffix: `bitcoin-node`, `lightning-node`, `fulcrum-node`, `liquid-node`, `monero-node`, `stacks-node`, `tor-node`, `i2pd-node`, `ipfs-node`

## Progress

### Done
- Repository renamed: `bitcoin` → `decentral-nodes` on GitHub
- rpk identity updated: `.rpk/identity` → `decentral-nodes`
- Package scripts updated: `configure`, `install`, `.rpk/package`
- Stacks script updated: pruning detection, chainstate archive download (.tar.zst format)
- Architecture decisions documented: JoinMarket, Storj, HNS, Yggdrasil in Tier 3
- Privacy architecture: selective Tor routing (not forced)
- **Tier 2 tools implemented**:
  - Tor daemon: `bin/tor-node`, `libexec/tor-node/daemon`, `libexec/tor-node/help`
  - I2Pd daemon: `bin/i2pd-node`, `libexec/i2pd-node/daemon`, `libexec/i2pd-node/help`
  - IPFS daemon: `bin/ipfs-node`, `libexec/ipfs-node/daemon`, `libexec/ipfs-node/help`

### In Progress
- Test Tor daemon enable/start on macOS
- Test IPFS daemon enable/start on macOS

### Tested
- **I2Pd daemon** (macOS): Working
  - Service: running (PID 37049)
  - SOCKS5: 127.0.0.1:4447
  - HTTP proxy: 127.0.0.1:4444
  - SAM bridge: 127.0.0.1:7656
  - Config: /opt/local/etc/i2pd/i2pd.conf (MacPorts)
  - Data: /opt/local/var/lib/i2pd

### Resolved
- Stacks chainstate archive now available at archive.hiro.so (205GB .tar.zst format)
- Archive URL: https://archive.hiro.so/mainnet/stacks-blockchain/mainnet-stacks-blockchain-latest.tar.zst
- Script updated to use .tar.zst format with zstd decompression

## Key Files
- `/Users/rene/Projekte/bitcoin/.rpk/identity`: Package identity (now `decentral-nodes`)
- `/Users/rene/Projekte/bitcoin/configure`: Build configuration
- `/Users/rene/Projekte/bitcoin/install`: Standalone installer
- `/Users/rene/Projekte/bitcoin/bin/tor-node`: Tor daemon dispatcher
- `/Users/rene/Projekte/bitcoin/libexec/tor-node/daemon`: Tor daemon implementation
- `/Users/rene/Projekte/bitcoin/bin/i2pd-node`: I2Pd daemon dispatcher
- `/Users/rene/Projekte/bitcoin/libexec/i2pd-node/daemon`: I2Pd daemon implementation
- `/Users/rene/Projekte/bitcoin/bin/ipfs-node`: IPFS daemon dispatcher
- `/Users/rene/Projekte/bitcoin/libexec/ipfs-node/daemon`: IPFS daemon implementation
- `/Users/rene/Projekte/bitcoin/libexec/stacks-node/daemon`: Stacks daemon script
- `/Users/rene/Projekte/bitcoin/STACKS_PRUNING.md`: Pruning issue documentation

## Critical Context
- Bitcoin prune height: 954729
- Stacks genesis block: 666050
- Error: "Timed out waiting for block data" / "I/O error when processing message"
- Archive.hiro.so is the only documented source (currently failing)
- All new tools will follow same rpk structure: `bin/<cmd>`, `libexec/<cmd>/`, `share/<cmd>/`