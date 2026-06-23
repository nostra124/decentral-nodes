# Stacks and Pruned Bitcoin Nodes

## Issue

Stacks **cannot sync from genesis with a pruned Bitcoin node**.

Your Bitcoin node is configured with `prune=550` (keeps only last 550 blocks). This causes Stacks to fail when trying to download historical blocks needed for initial sync.

## Evidence

```
Bitcoin prune height: 954729
Stacks genesis block: 666050

Error: "Timed out waiting for block data"
Error: "I/O error when processing message"
```

Stacks tries to sync from block 666050, but blocks below 954729 have been pruned and are unavailable.

## Solution

The `libexec/stacks/daemon` script now automatically:

1. **Detects pruning**: Checks if Bitcoin config has `prune=` setting
2. **Downloads chainstate archive**: Attempts to download pre-synced Stacks blockchain from:
   - https://archive.hiro.so/mainnet/stacks-blockchain/mainnet-stacks-blockchain-latest.tar.gz
   - Backup URL: https://storage.googleapis.com/stacks-archive/mainnet/stacks-blockchain/mainnet-stacks-blockchain-latest.tar.gz
3. **Extracts to correct location**: Places chainstate in `/var/lib/stacks/mainnet/`
4. **Provides clear instructions**: If download fails, warns user about manual options

## Manual Archive Download

If automatic download fails, manually download and extract:

```bash
# Download archive
curl -L https://archive.hiro.so/mainnet/stacks-blockchain/mainnet-stacks-blockchain-latest.tar.gz -o /tmp/stacks-archive.tar.gz

# Verify it's a valid archive
file /tmp/stacks-archive.tar.gz  # Should show "gzip compressed data"

# Extract
sudo tar -xzf /tmp/stacks-archive.tar.gz -C /var/lib/stacks/

# Set permissions
sudo chown -R _stacks:_stacks /var/lib/stacks
```

## Alternative: Disable Pruning

If you want Stacks to sync from genesis (not recommended, takes days):

1. Remove `prune=550` from `/opt/local/etc/bitcoin/bitcoin.conf`
2. Restart Bitcoin (will need to re-download full blockchain ~500GB)
3. Wait for full sync
4. Then Stacks can sync from genesis

## References

- Stacks Documentation: https://docs.stacks.co/operate/run-a-node/run-a-pruned-bitcoin-node.md
- Archive Source: https://archive.hiro.so/mainnet/stacks-blockchain/

## Current Status

- **Bitcoin**: healthy (pruned at block 954729)
- **Lightning**: healthy
- **Monero**: healthy  
- **Liquid**: syncing
- **Stacks**: waiting for chainstate archive (cannot sync from genesis with pruned Bitcoin)