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
- Commands remain unchanged: `bitcoin`, `lightning`, `fulcrum`, `liquid`, `monero`, `stacks`, etc.

## Progress

### Done
- Repository renamed: `bitcoin` → `decentral-nodes` on GitHub
- rpk identity updated: `.rpk/identity` → `decentral-nodes`
- Package scripts updated: `configure`, `install`, `.rpk/package`
- Stacks script with pruning detection and fail-safe
- Architecture decisions documented: JoinMarket, Storj, HNS, Yggdrasil in Tier 3
- Privacy architecture: selective Tor routing (not forced)

### In Progress
- Stacks blocked: archive.hiro.so URLs returning 404
- Awaiting chainstate archive or alternative approach

### Blocked
- Stacks cannot sync from genesis with pruned Bitcoin node
- Bitcoin prune height: 954729 (blocks below unavailable)
- Stacks needs block 666050 (below prune height)
- Archive URLs failing with 404

## Key Files
- `/Users/rene/Projekte/bitcoin/.rpk/identity`: Package identity (now `decentral-nodes`)
- `/Users/rene/Projekte/bitcoin/configure`: Build configuration
- `/Users/rene/Projekte/bitcoin/install`: Standalone installer
- `/Users/rene/Projekte/bitcoin/libexec/stacks/daemon`: Stacks daemon script
- `/Users/rene/Projekte/bitcoin/STACKS_PRUNING.md`: Pruning issue documentation

## Critical Context
- Bitcoin prune height: 954729
- Stacks genesis block: 666050
- Error: "Timed out waiting for block data" / "I/O error when processing message"
- Archive.hiro.so is the only documented source (currently failing)
- All new tools will follow same rpk structure: `bin/<cmd>`, `libexec/<cmd>/`, `share/<cmd>/`