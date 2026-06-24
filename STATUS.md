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
| m2pd | Tier 2 | I2P network daemon (P2P bootstrap capable) |
| Whonix | Tier 3 | VM-based isolation (later stage) |

### Privacy Architecture
- **Selective Tor routing**: Services opt-in to Tor, not all traffic forced through Tor
- Tor/m2pd daemons run as system services (Tier 2)
- Applications connect through Tor when needed (opt-in basis)
- JoinMarket can operate over Tor (Tier 3)

### Naming
- Repository: `decentral-nodes`
- rpk package identity: `decentral-nodes`
- Commands use `-node` suffix: `bitcoin-node`, `lightning-node`, `fulcrum-node`, `liquid-node`, `monero-node`, `stacks-node`, `tor-node`, `ipfs-node`, `joinmarket-node`, `storj-node`

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
  - IPFS daemon: `bin/ipfs-node`, `libexec/ipfs-node/daemon`, `libexec/ipfs-node/help`
- **Tier 3 tools implemented**:
  - JoinMarket: `bin/joinmarket-node`, `libexec/joinmarket-node/daemon`, `libexec/joinmarket-node/help`
  - Storj: `bin/storj-node`, `libexec/storj-node/daemon`, `libexec/storj-node/help`

### In Progress
- m2pd (I2P network daemon): Source at `/Users/rene/Projekte/m2pd`, needs integration wrapper
- IPFS daemon: Installed, wrapper exists, needs launchd fix
- JoinMarket: Wrapper created, needs testing
- Storj: Wrapper created, needs testing

### Tested
- **m2pd daemon** (macOS, balmung): Working with P2P bootstrap
  - Fork: https://github.com/nostra124/m2pd (private)
  - Feature: `--bootstrap=<host:port>` for peer-to-peer bootstrap
  - Feature: `/routerInfo` HTTP endpoint for peer bootstrapping
  - Installed: `/usr/local/bin/m2pd` on local macOS
  - Installed: `/usr/sbin/m2pd` on balmung
   
- **Tor daemon** (macOS): Working
  - Service: running
  - SOCKS5: 127.0.0.1:9050
  - Control: 127.0.0.1:9051
  - Selective routing: opt-in via SOCKS5

### Known Issues & Solutions
- **m2pd P2P bootstrap**: Use `--bootstrap=<host:port>` to bootstrap from a trusted peer instead of centralized reseed servers.
   
  ```bash
  # On server (running m2pd with HTTP console on 0.0.0.0):
  m2pd --conf=/etc/m2pd/m2pd.conf
  
  # On client (new instance):
  m2pd --bootstrap=server.example.com:7070
  ```

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
- `/Users/rene/Projekte/bitcoin/bin/ipfs-node`: IPFS daemon dispatcher
- `/Users/rene/Projekte/bitcoin/libexec/ipfs-node/daemon`: IPFS daemon implementation
- `/Users/rene/Projekte/bitcoin/bin/joinmarket-node`: JoinMarket daemon dispatcher
- `/Users/rene/Projekte/bitcoin/libexec/joinmarket-node/daemon`: JoinMarket daemon implementation
- `/Users/rene/Projekte/bitcoin/bin/storj-node`: Storj node dispatcher
- `/Users/rene/Projekte/bitcoin/libexec/storj-node/daemon`: Storj node implementation
- `/Users/rene/Projekte/bitcoin/libexec/stacks-node/daemon`: Stacks daemon script
- `/Users/rene/Projekte/bitcoin/STACKS_PRUNING.md`: Pruning issue documentation

## Critical Context
- Bitcoin prune height: 954729
- Stacks genesis block: 666050
- Error: "Timed out waiting for block data" / "I/O error when processing message"
- Archive.hiro.so is the only documented source (currently failing)
- All new tools will follow same rpk structure: `bin/<cmd>`, `libexec/<cmd>/`, `share/<cmd>/`