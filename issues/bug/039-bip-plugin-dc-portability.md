---
id: BUG-039
type: bug
priority: high
status: open
---

# BIP plugins compute wrong results on the macOS `dc`: line-wrapping corrupts long output, and the bip32 engine needs GNU dc

## Severity

**High.** The BIP-340/341/32/39 plugins silently produce *wrong* (but
well-formed, deterministic) cryptographic output on any host whose `dc` wraps
long output — which includes the current macOS/Homebrew default. Schnorr
sign/verify, Taproot tweaks, and HD derivation all fail for real 256-bit
scalars while small-scalar tests pass, so the breakage hides until a full
vector run. ~90 unit tests (FEAT-007/008 and the wallet-derive suites) fail on
such a host even though the code is correct, defeating the local unit gate
(CLAUDE.md §9).

## Observed

On this box (`dc` = Gavin Howard's `dc 7.0.3`, the macOS default):

```
$ bitcoin bip340 pubkey 0000…0003            # small scalar
F9308A019258C31049344F85F89D5229B531C845836F99B08601F113BCE036F9   # correct
$ bitcoin bip340 pubkey B7E1…CFEF            # 256-bit scalar
904678F58380B0096602C4799BEA0C86844BB8E95DCCF12FD5FAC60DE113916F   # WRONG
                                             # (expected DFF1D77F…502BA659)
```

`ec_mul` decomposes the scalar to bits with a recursive `dc` macro that prints
one long line:

```sh
bits=$(dc -e "16i $k [d 2 % n 2 / d 0 <L] d sL x")   # LSB-first 0/1 chars
```

For a 256-bit scalar `dc` wraps that 256-char line at its column limit (70) with
a `\`+newline, so `$bits` comes back length 262 containing literal `\` and
newline characters. The double-and-add loop then reads those as "bits", silently
dropping/garbling the high bits — hence correct small scalars, wrong large ones.
The same corruption applies to any long `dc` output the plugins parse (bip39
entropy/checksum bit strings, bip32 EC coordinates near the wrap width).

## Root cause

`dc` wraps long numeric output across lines with `\`+newline by default. Both
Gavin Howard's `dc` and GNU `dc` honour the `DC_LINE_LENGTH` environment
variable; `DC_LINE_LENGTH=0` disables wrapping. The plugins never set it, so
output longer than the column limit is corrupted when parsed. Small scalars
(short output) never wrap, which is why the bug stayed latent and passed in
environments whose `dc` happened not to wrap.

## Fix

`export DC_LINE_LENGTH=0` once near the top of each `dc`-using BIP plugin
(`libexec/bitcoin/bip340`, `bip341`, `bip32`, `bip39`, `bip13`). Disabling
wrapping is always safe — we only ever parse `dc` output programmatically and
never want intra-number line breaks. Keeps the no-shared-lib policy (CLAUDE.md
§4/§5): each plugin sets it for its own primitives.

## Second root cause: `bip32` requires GNU dc

`libexec/bitcoin/bip32`'s secp256k1 engine (the dense `$secp256k1` dc program)
packs bytes by setting the output radix to `2^100`. **GNU dc** tolerates that
(it warns "output base must be …" and continues), but **Gavin Howard's dc** —
the current macOS/Homebrew default `/usr/bin/dc` — treats it as a hard
`Math error: overflow: number cannot fit` and aborts mid-derivation, silently
returning a wrong child key. This is *not* the line-wrap issue (the HMAC inputs
and outputs are byte-identical across dc implementations; only the engine's
radix trick diverges) and `DC_LINE_LENGTH=0` does not address it. It breaks
every derivation-dependent path: `wallet derive` (FEAT-013/044), `descriptor
derive` / `bip380 derive` (FEAT-026), and the `wallet build`/`sign`/`send` and
`psbt` flows that derive an address first (FEAT-014/008/018/038).

Reproduced: `bip380 derive "tr(<bip86-account-xpub>/0/*)" 0` returns
`bc1pw992htk…` (wrong) under `/usr/bin/dc` and the correct BIP-86 address
`bc1p5cyxnuxm…` once a GNU dc derives the child key
(`03cc8a4bc6…cd6fc115`).

### Fix

`bip32` resolves a GNU-compatible `dc` once (`DC_BIN`) and routes its coproc
through it. It probes each candidate (`dc` on PATH, then
`$HOMEBREW_PREFIX/opt/bc/bin/dc`, `/usr/local/opt/bc/bin/dc`, `gdc`) with the
`2^100`-radix trick the engine needs and picks the first that survives. On
Linux the PATH `dc` is GNU dc, so the first probe wins and this is a no-op; on
macOS it falls through to a Homebrew/MacPorts GNU dc (`brew install bc`). If
none is found it `warn`s and falls back to PATH `dc` (which then errors loudly
rather than silently corrupting). bip32 has a single `dc` call site (the
coproc), so this is the only change needed.

## Regression test

`tests/unit/bip340.bats` (and `bip341` / the wallet-derive suites) fail against
the unset-`DC_LINE_LENGTH` plugins on a wrapping `dc` and pass once
`DC_LINE_LENGTH=0` is exported. The official BIP-340 vectors (large-scalar sign
sk=3 round-trip, verify vectors 0/4) are the proof points.
