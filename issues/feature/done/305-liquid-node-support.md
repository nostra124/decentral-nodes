---
id: FEAT-305
type: feature
priority: high
status: done
depends_on:
  - FEAT-001  # dispatcher pattern
  - FEAT-183  # daemon lifecycle (lightning pattern)
  - FEAT-267  # system-mode (macports-first)
milestone: 3.4.0
---

# Liquid Network node support

## Summary

Add `liquid` as the fifth dispatcher in the bitcoin package, providing
node lifecycle, wallet, and peg operations for the Liquid Network (Bitcoin
sidechain with confidential transactions and issued assets).

## Motivation

Liquid is a federated Bitcoin sidechain with:
- Confidential transactions (blinded amounts/addresses)
- Issued assets (stablecoins like L-USDT, securities, NFTs)
- 1-minute block times (vs 10min Bitcoin)
- Native atomic swap support via Elements

For Bitcoin operators running this stack, Liquid is a natural extension:
same UTXO model, same Elements codebase as Lightning, complementary
privacy layer.

## Surface

```
bin/liquid                         # dispatcher (FEAT-001 pattern)

libexec/liquid/
├── daemon                         # elementsd lifecycle
│   ├── install                    # brew | apt | source
│   ├── enable [--system|--user]   # launchd/systemd
│   ├── start|stop|restart|status
│   └── monitor                    # tail log
├── config                         # elements.conf management
├── wallet                         # L-BTC wallet
│   ├── new <name>                 # create wallet
│   ├── list                       # list wallets
│   ├── balance                    # blinded balance
│   └── address                    # getaddress, validate
├── peg                            # two-way peg
│   ├── in                         # BTC → L-BTC (peg-in)
│   ├── out                        # L-BTC → BTC (peg-out)
│   └── status                     # pending pegs
└── asset                          # issued assets (future)
    ├── issue                      # create asset
    ├── transfer                   # send asset
    └── balance                     # asset balances
```

## Implementation Phases

### Phase 1: Node lifecycle (3.4.0) ✅ DONE

Mirror `bitcoin daemon` and `lightning daemon`:

1. **`liquid daemon install`**
   - Source: elementsproject/elements (GitHub releases)
   - MacPorts: `sudo port install elements`
   - Homebrew: `brew install elements`
   - Binary: same pattern as `lightning daemon install`

2. **`liquid daemon enable --system`**
   - macOS: `_liquid` user, `/var/lib/liquid`, `/Library/LaunchDaemons/network.liquid.elementsd.plist`
   - Linux: `liquid` user, `/var/lib/liquid`, systemd unit
   - Config: `/etc/liquid/elements.conf`

3. **`liquid daemon status`**
   - Same RPC detection as `lightning daemon status`
   - Check `elements-cli getblockchaininfo` via RPC cookie

4. **`liquid daemon start|stop|restart|monitor`**
   - Same pattern as `lightning daemon`

### Phase 2: Wallet surface (3.4.0) ✅ DONE

1. **`liquid wallet new <name>`**
   - `elements-cli createwallet <name>`

2. **`liquid wallet balance`**
   - `elements-cli getbalance` (confidential)

3. **`liquid wallet address`**
   - `getnewaddress` — confidential address

### Phase 3: Peg operations (3.4.0) ✅ DONE

1. **`liquid peg in`**
   - Get peg-in address from federation
   - User sends BTC to that address

2. **`liquid peg claim <txid>`**
   - Claim L-BTC after 102 confirmations

3. **`liquid peg out <address> <amount>`**
   - Burn L-BTC, receive BTC
   - `sendtomainchain` Elements command

4. **`liquid peg status <id>`**
   - Check peg-out status

### Phase 4: Assets (future, optional)

Issued assets (stablecoins, securities):
- `liquid asset issue <name> <amount>`
- `liquid asset transfer <asset-id> <address> <amount>`
- `liquid asset balance <asset-id>`

## System Integration

### macOS (launchd)

```
/Library/LaunchDaemons/network.liquid.elementsd.plist

UserName: _liquid
GroupName: _liquid
ProgramArguments:
  /opt/homebrew/bin/elementsd
  --datadir=/var/lib/liquid
  --conf=/etc/liquid/elements.conf
```

### Config file

```
# /etc/liquid/elements.conf
network=liquidtest  # or liquid (mainnet)
rpcuser=liquid
rpcpassword=<generated>
daemon=1
```

### Cookie auth

Like Bitcoin, Elements uses cookie auth by default:
```
/var/lib/liquid/.cookie
```

Same `daemon:_resolve_bitcoin_cli` pattern for `elements-cli`.

## Shared Code

Reuse from `bitcoin daemon` and `lightning daemon`:

| Function | Location | Reuse |
|----------|----------|-------|
| `daemon install` | install script | Same brew/apt/source pattern |
| `daemon enable --system` | launchd plist template | Same `_user` / `/var/lib/<product>` pattern |
| `daemon status` | RPC detection via cookie | Same `cli getinfo` pattern |
| `daemon start/stop` | supervisor integration | Identical |

## Dependencies

- **Elements**: The Liquid implementation (elementsproject/elements)
- **elements-cli**: RPC client (ships with Elements)
- **bitcoin daemon**: Peg operations require a running bitcoind

## Testing

Follow existing pattern:
- `tests/unit/liquid.bats` — unit tests (mocked elements-cli)
- `tests/sit/` — system integration (requires elementsd)

## References

- [Elements Project](https://elementsproject.org/)
- [Liquid Network](https://liquid.net/)
- [Elements codebase](https://github.com/elementsproject/elements)