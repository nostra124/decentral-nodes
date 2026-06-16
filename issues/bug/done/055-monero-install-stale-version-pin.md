---
id: BUG-055
type: bug
status: closed
---

# monero install pins a version that goes stale, so a fresh install fail-closes

## Severity

**Medium.** `monero install` hardcoded `MONERO_VERSION=v0.18.3.4` and built the
asset name from it, then checked that name against the (verified) hashes file.
Once getmonero.org publishes a newer release, the pinned asset is no longer in
the current hashes → the install correctly fail-closes ("not listed in the
verified hashes") but can **never succeed** until someone edits the pin. A
fresh deploy of monero was impossible out of the box.

## Observed

Live deploy, June 2026 (getmonero.org on v0.18.5.0):

```
$ monero install
install: info  - release: v0.18.3.4  asset: monero-mac-armv8-v0.18.3.4
install: info  - hashes signature verified (binaryFate)
install: error - monero-mac-armv8-v0.18.3.4.tar.bz2 is not listed in the
                 verified hashes file — aborting
```

`hashes.txt` listed `monero-mac-armv8-v0.18.5.0.tar.bz2`; the pinned
`v0.18.3.4` was gone.

## Root Cause

The version was a hardcoded default (`MONERO_VERSION="${MONERO_VERSION:-v0.18.3.4}"`)
and `monero:_asset` baked it into the asset name *before* the hashes were even
fetched. The install never tracked the current release.

## Fix Plan

- Drop the hardcoded default: `MONERO_VERSION="${MONERO_VERSION:-}"` (empty =
  no pin). An explicit `$MONERO_VERSION` / `--version` still pins.
- `monero:_asset` → `monero:_asset_prefix` (no version).
- After GPG-verifying the hashes, `monero:_resolve_asset` finds the CLI
  tarball line `<sha>  <prefix>-v<X.Y.Z.W>.tar.bz2` (never `-gui-`), honouring
  the pin when set; extract the version from it. Move the idempotency check
  after this resolve.

## Regression Protection

`tests/unit/monero.bats`: the fixture takes a version arg.

```bats
@test "BUG-055: install auto-detects the version from the verified hashes (no stale pin)" {
	_mk_release_fixture x86_64 v0.18.5.0
	unset MONERO_VERSION
	run "$MONERO" install --prefix "$REL_PREFIX"
	[ "$status" -eq 0 ]
	[[ "$output" == *"release: v0.18.5.0"* ]]
	[ -x "$REL_PREFIX/monerod" ]
}
@test "BUG-055: an explicit --version pin the hashes don't list fails closed" { ... }
```

Fails on the old hardcoded-pin code (constructs v0.18.3.4, not in the v0.18.5.0
hashes → aborts), passes after the fix.

## Acceptance Criteria

1. With no pin, `monero install` tracks whatever the verified hashes publish.
2. An explicit `--version` not present in the hashes fails closed.
3. GPG + SHA256 verification unchanged (still fail-closed on tampering).
