# `bitcoin` command surface — the two-surface model

> Architecture doc pinned by ROADMAP-1.23.0 (FEAT-035).
> Lives in `docs/` so it survives across milestones.

## Why two surfaces

`bitcoin` is **educational** first and **a real wallet** second.
Those two missions don't fit one command vocabulary:

- A learner reading **BIP-32** wants `bitcoin bip32 derive
  m/84'/0'/0' <xprv>` — verbatim from the spec, no wallet
  ceremony around it.
- An operator building a transaction wants `bitcoin tx build
  --to bc1q... --amount 0.01 --from <wallet>` — the BIP layers
  are an implementation detail, not the noun.

Conflating the two punishes both audiences: the learner has to
peel back wallet state to see the primitive, and the operator
has to know which BIP backs which verb to compose anything.

The solution: **two parallel surfaces**, one BIP-faithful and
one object-flexible, with explicit composition between them.

## Surface 1 — BIP plugins (`bipXXX`)

Every BIP we implement gets its own plugin under
`libexec/bitcoin/bipXXX`. The plugin's verbs match the BIP's
own vocabulary as closely as bash allows:

| Plugin   | BIP       | Verbs (illustrative)                       |
|----------|-----------|---------------------------------------------|
| `bip13`  | BIP-13    | `address-from-hash`                         |
| `bip32`  | BIP-32    | `derive`, `neuter`, `master-from-seed`      |
| `bip39`  | BIP-39    | `mnemonic`, `mnemonic-to-seed`, `validate`  |
| `bip173` | BIP-173   | `encode`, `decode` (bech32 / segwit v0)     |
| `bip174` | BIP-174   | `encode`, `decode`, `sign`, `finalize`, `extract` (PSBT) |
| `bip340` | BIP-340   | `sign`, `verify` (Schnorr; FEAT-007)        |
| `bip341` | BIP-341   | `tweak`, `script-path-sign` (Taproot; FEAT-007) |
| `bip342` | BIP-342   | `tapscript-sig` (FEAT-007)                  |
| `bip350` | BIP-350   | `encode`, `decode` (bech32m / segwit v1+)   |
| `bip380` | BIP-380   | `create`, `verify`, `derive`, `emit`        |

Rules for the surface:

1. **Self-contained.** A `bipXXX` plugin reads its inputs from
   args / stdin, writes the BIP-defined output to stdout, exits
   non-zero on a BIP-defined failure, and cites the BIP at the
   top of the file (per repo convention). It calls only its
   primitives (openssl, awk) — never another `bipXXX` plugin and
   never the dispatcher.
2. **No wallet state.** The plugin doesn't read `secret`, doesn't
   touch `~/.bitcoin/wallets/`, doesn't know the active backend.
   It's pure crypto/encoding.
3. **Vectorable.** Every plugin has a `tests/vectors/bipXXX.*`
   companion that drives it against the BIP's appendix vectors.
   This is the regression baseline.

## Surface 2 — object verbs

Top-level nouns the operator works with:

| Verb       | Job                                               |
|------------|----------------------------------------------------|
| `wallet`   | Wallet lifecycle: `new`, `ls`, `rm`, `push`, `pull`, `balance`, `history`, `send` (high-level convenience). |
| `account`  | (Sibling tool — not in `bitcoin` itself.)         |
| `tx`       | Transactions: `build`, `sign`, `decode`, `broadcast`, `bump` (FEAT-036). |
| `utxo`     | UTXOs: `ls`, `freeze`, `unfreeze`, `select` (FEAT-037). |
| `address`  | Addresses: `derive`, `ls`, `label`, `qr` (rolled out of `wallet` as needed). |
| `daemon`   | Bitcoin Core lifecycle: `install`, `enable`, `disable`, `start`, `stop`, `monitor`, `space`. |
| `backend`  | RPC backend selection: `set`, `auto`, `broadcast`. |
| `tax`      | Tax reports: `report-de` (FEAT-039), `label` (shorthand for `wallet label`). |

Rules for the surface:

1. **Composes BIP plugins.** Every cryptographic step in an
   object verb is a `bipXXX` call. `tx sign` calls `bip174 sign`.
   `wallet new` calls `bip39 mnemonic` + `bip32 master-from-seed`
   + `bip380 emit`. No object verb reimplements crypto.
2. **Sparrow-flex as the bar.** The object surface targets the
   range of operations Sparrow Wallet exposes — coin control,
   labeling, fee-bumping, PSBT round-tripping with hardware —
   but as composable CLI verbs rather than a GUI.
3. **State lives here.** Wallet ledger, label store, address
   index, fee cache — all under `~/.bitcoin/wallets/<name>/`
   per existing convention.

## Migration table (what 1.23.0 changes)

| Before (today)                       | After (1.23.0)                                          | Notes |
|--------------------------------------|----------------------------------------------------------|-------|
| `bitcoin psbt {decode,encode,...}`   | `bitcoin bip174 {decode,encode,...}` (canonical)         | `psbt` kept as deprecated alias for one release. |
| `bitcoin descriptor {create,...}`    | `bitcoin bip380 {create,verify,derive,emit}`             | `descriptor` kept as deprecated alias for one release. |
| (bech32 helpers inside `bin/bitcoin`)| `bitcoin bip173 {encode,decode}`, `bitcoin bip350 {encode,decode}` | Helpers move out of the dispatcher into plugins. |
| `bitcoin mnemonic-to-seed`           | `bitcoin bip39 mnemonic-to-seed`                         | Fold the standalone libexec file under `bip39`. |
| `bitcoin wallet build/sign/broadcast`| `bitcoin tx build/sign/broadcast` (canonical); `wallet send` stays as convenience | Object verb `tx` extracted from `wallet`. |
| `bitcoin wallet index` (UTXO state)  | `bitcoin utxo ls` (canonical); `wallet index` kept as alias | Object verb `utxo` extracted from `wallet`. |
| `bitcoin wallet label`               | `bitcoin wallet label` (unchanged) + `bitcoin tax label` shorthand | Label vocabulary expands (FEAT-038). |

## Deprecation policy

Renamed verbs ship as **deprecated aliases** for one release.
The alias emits a `warn` line per `skills/logging.md` naming
the canonical form. The alias is removed in the next minor
release (1.24.0 removes the 1.23.0 aliases).

## Non-goals for the streamline

- **No behavior changes** in 1.23.0. The streamline is rename +
  re-shelve; vector tests must pass byte-for-byte against the
  old and new names.
- **No new BIP implementations** in 1.23.0. Schnorr/Taproot
  (FEAT-007) waits for 1.26.0 so it lands cleanly into the new
  `bip340/341/342` slots.
- **No new object verbs beyond `tx` and `utxo`** in 1.23.0.
  `address` rolls out of `wallet` as Sparrow-flex features
  demand it (1.24.0+).
