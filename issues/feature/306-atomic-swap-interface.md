---
id: FEAT-306
type: feature
priority: medium
status: draft
depends_on:
  - FEAT-012  # bitcoin backend abstraction
  - FEAT-183  # lightning daemon
milestone: 3.5.0
---

# Atomic swap interface (BTC ↔ ETH, L-BTC ↔ BTC)

## Summary

Provide a `swap` verb across `bitcoin`, `lightning`, and `liquid` for
cross-chain atomic swaps — **without** managing full Ethereum/Liquid nodes.
The swap verb interfaces with **bridge protocols** and **atomic swap
services** rather than running the target chain's node.

## Motivation

Operators running this Bitcoin stack often need:
1. BTC ↔ ETH swaps (diversification, DeFi exposure)
2. LN ↔ L-BTC swaps (confidential Lightning)
3. BTC ↔ L-BTC peg (native Liquid peg, not DEX)

Rather than managing full Ethereum and Liquid nodes, we can interface
with:
- **Thorchain** — decentralized cross-chain liquidity
- **Liquality** — atomic swap protocol
- **Boltz** — LN ↔ L-BTC submarine swaps
- **Liquid federation** — native peg

## Design Principle

> **No full node for the target chain.**
> 
> The swap verb queries swap services, constructs the source-chain side,
> and tracks the swap status. The user provides a destination address for
> the target chain (which they may manage via MetaMask, Ledger, etc.)

This keeps the package focused while enabling cross-chain operations.

## Surface

### Bitcoin dispatcher

```
bin/bitcoin swap btc-eth <btc-amount> <eth-address>
                     [--service thorchain|liquality]
                     [--slippage <percent>]
                     [--timeout <blocks>]

# Output: deposit address, swap ID, estimated ETH amount
# User sends BTC → deposit address
# Service handles BTC → ETH swap
# User receives ETH at <eth-address>
```

### Lightning dispatcher

```
bin/lightning swap ln-eth <msats> <eth-address>
                         [--service thorchain|boltz]
                         [--timeout <blocks>]

bin/lightning swap ln-lbtc <msats> <liquid-address>
                           [--service boltz]
```

### Liquid dispatcher

```
bin/liquid swap lbtc-btc <lbtc-amount> <btc-address>
                         [--service liquid-federation|dex]

bin/liquid peg in <btc-utxo>   # native peg (not swap)
bin/liquid peg out <lbtc-utxo> # native peg (not swap)
```

## Architecture

### No Ethereum node required

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  bitcoin swap   │────▶│  Thorchain API   │────▶│  Ethereum       │
│  (source chain) │     │  (swap service)  │     │  (dest chain)   │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                              │
                              ▼
                     User's ETH address
                     (managed externally)
```

The swap verb:
1. Queries Thorchain/Liquality for swap rate
2. Displays estimated output + fees
3. Generates a Bitcoin deposit address (owned by swap service)
4. Monitors the swap status via API polling
5. Reports when ETH is sent to user's address

### Swap service integration

```
libexec/bitcoin/swap-btc-eth     # Thorchain / Liquality client
libexec/lightning/swap-ln-eth    # Thorchain / Boltz for LN
libexec/lightning/swap-ln-lbtc   # Boltz submarine swap
```

Each swap client:
- Queries the service API for rates/quotes
- Generates the deposit address / invoice
- Polls for swap completion
- Writes swap status to `$XDG_DATA_HOME/<cmd>/swaps/<swap-id>.json`

## Implementation Phases

### Phase 1: Thorchain BTC ↔ ETH (3.5.0)

Thorchain is the most mature cross-chain DEX:
- Native BTC support (no wrapped assets)
- Decentralized liquidity pools
- Simple API: `POST /swap` with source/dest

```
bitcoin swap btc-eth 0.1 0x1234... --service thorchain

# 1. Query Thorchain rate API
# 2. Calculate slippage, display quote
# 3. Generate inbound BTC address
# 4. Monitor inbound tx
# 5. Poll for outbound ETH tx
# 6. Report completion
```

### Phase 2: Boltz LN ↔ L-BTC (3.6.0)

Boltz submarine swaps for Lightning ↔ Liquid:
- User sends LN invoice
- Boltz holds HTLC on both chains
- Atomic: either both sides complete or neither

```
lightning swap ln-lbtc 1000000 lq1... --service boltz

# 1. Query Boltz API for submarine swap quote
# 2. Generate LN invoice for amount
# 3. Boltz creates L-BTC HTLC
# 4. User pays LN invoice
# 5. Boltz releases L-BTC to user's address
```

### Phase 3: Liquality support (3.7.0)

Liquality is an atomic swap protocol:
- No trusted third party
- Hash time-locked contracts on both chains
- User controls both sides of the swap

More complex setup, but trustless.

## Risk Model

| Service | Trust Model | Atomicity | Notes |
|---------|-------------|-----------|-------|
| Thorchain | Federation + threshold sig | Yes | Decentralized, battle-tested |
| Boltz | Single operator | Yes | HTLC-based, atomic |
| Liquality | None (HTLC) | Yes | Trustless, complex UX |
| Liquid federation | Federation (15 members) | Yes | Native peg, not swap |

The swap verb surfaces the trust model to the user:
```
bitcoin swap btc-eth 0.1 0x... --service thorchain
# Warns: "Thorchain is a federated cross-chain DEX. Your BTC is sent
# to a Thorchain vault and released when the ETH swap completes.
# Estimated time: 10-30 minutes."
```

## Swap Status Tracking

All swaps are persisted for audit:

```
$XDG_DATA_HOME/bitcoin/swaps/2024-06-22-<swap-id>.json

{
  "swap_id": "thor-abc123",
  "service": "thorchain",
  "source_chain": "bitcoin",
  "dest_chain": "ethereum",
  "source_amount_sats": 10000000,
  "dest_amount_wei": 1500000000000000000,
  "source_txid": "...",
  "dest_txid": "...",
  "status": "completed",
  "created_at": "2024-06-22T10:00:00Z",
  "completed_at": "2024-06-22T10:15:00Z"
}
```

`bitcoin swap list` shows all historical swaps.

## Dependencies

- `curl` or `wget` for API calls
- `jq` for JSON parsing
- External: Thorchain/Boltz/Liquality API endpoints (public or self-hosted)

## Security Considerations

1. **API endpoint validation** — Verify HTTPS, certificate pinning
2. **Quote verification** — Compare rate against multiple sources
3. **Timeout enforcement** — Abort if swap doesn't complete in expected window
4. **No private key exposure** — Source chain signs, dest chain is external

## Testing

- `tests/unit/swap.bats` — Mock API responses, verify quote calculation
- `tests/sit/` — Integration tests against testnet services

## References

- [Thorchain API](https://docs.thorchain.org/)
- [Boltz API](https://docs.boltz.exchange/)
- [Liquality Protocol](https://liquality.io/)
- [Liquid Peg](https://help.liquid.net/the-liquid-peg-in-and-peg-out)