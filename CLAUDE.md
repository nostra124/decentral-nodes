# `bitcoin` — developer notes

> Mirrors `CLAUDE.md.foundation`, specialised for the
> combined educational Bitcoin stack.

## 0. Combined stack (multi-command repo)

This repo ships the **full Bitcoin stack from one rpk
package** (`.rpk/identity` = `bitcoin`) via multiple
command dispatchers:

- `bin/bitcoin` + `libexec/bitcoin/*` — BIP plugins +
  wallet (this file's §§1–13).
- `bin/lightning` + `libexec/lightning/*` — the Core
  Lightning frontend, **merged in from
  `nostra124/lightning`**. Its developer notes live at
  `docs/templates/CLAUDE.md.lightning`; the Lightning
  scope, no-shared-lib rules (it depends on `python3`
  + `sqlite3`, runs the `.well-known/lightning/` CGI),
  three-user model, and man-page contract all carry
  over unchanged.
- `bin/fulcrum` — *planned* (FEAT-055..060), slots into
  the same layout.

Each command keeps its own namespaced `libexec/<cmd>/`,
`share/<cmd>/`, `share/doc/<cmd>/`, and
`share/man/man1/<cmd>-*.1`. The dispatchers resolve
their libexec by binary name, so they coexist with no
cross-wiring. **`bitcoin` and `lightning` never shell
out to each other** (§4); the on-chain leg of a channel
open is handled by clightning's own bitcoind connection.

The combined contract is the union of
`tests/unit/bitcoin.bats` and `tests/unit/lightning.bats`
(plus `tests/python/` for the CGI layer).

## 1. Scope

`bitcoin` (the command) is the educational Bitcoin
frontend. Its scope is the BIP plugins (BIP 13/32/39/
173, WIF, the daemon abstraction) plus a wallet surface.

Out of scope for the `bitcoin` command: Lightning
(that's the `lightning` command, §0); on-chain
transaction-history indexing for the whole network
(out of scope for an educational tool).

**Daemon posture (3.0.0/3.1.0, FEAT-261/262/264).** The
default daemon mode for `bitcoin daemon`, `fulcrum`, and
`lightning daemon` is `--system` — a boot-persistent
service under a dedicated account, the reliable substrate
other software builds on. `--user` is retained as the
explicit rootless opt-in for personal/educational, macOS,
and CI use. bitcoin/fulcrum flipped in 3.0.0; lightning
flipped in 3.1.0 (only the `enable` install default —
its operate verbs keep auto-detecting the installed mode,
and its user-mode sidecars stay `--user`-only).

## 2. Repo conventions

Standard rpk per-package: `bin/bitcoin` dispatcher
plus libexec lookup for BIP plugins. Each plugin under
`libexec/bitcoin/<bip>` cites the BIP it implements.
The upstream packaging and skill conventions this repo
mirrors live at <https://github.com/nostra124/rpk>
(`docs/PACKAGING.md` is the authority for the `.rpk/`
contract and the agent-skill install layout).

Educational package: vendors BIP source documents
under `share/doc/bitcoin/bips/` (FEAT-017) and
ships a walkthrough at `docs/bitcoin-walkthrough.md`
(FEAT-015, closed 1.29.0).

The wallet model: **seed phrase lives in `secret`,
not in `bitcoin`**. Wallet verbs read the seed via
`secret get <wallet>/seed` on demand.

## 3. Issue authoring

Same as `CLAUDE.md.foundation`. **Bugs come before
features at the same priority level.**

Bug workflow is test-driven: every fix lands with a
regression test that demonstrably failed against the
broken code first. See `skills/bugs.md`.

Feature workflow is acceptance-criteria-driven: every
feature lands with the tests its acceptance criteria
imply. See `skills/features.md`.

## 4. The no-shared-lib policy

`bitcoin` calls only `account`, `config`, `secret`, and `crypt` at
runtime. BIP plugins call only their own primitives
(openssl for hashing, awk for encoding, dc for arithmetic,
xxd for hex I/O); never a shared crypto-helpers library.

The dependency boundary is enforced by two bats tests in
`tests/unit/bitcoin.bats` (FEAT-195, closed 1.30.0).
Forbidden sibling calls (`cache`, `data`, `hosts`, `scripts`, `task`)
fail CI if re-introduced.

## 5. What is intentionally duplicated

- **Base58 / Bech32 encoding** could be shared with
  `crypt` but is reimplemented per plugin so each is
  self-contained.
- **HD-derivation logic** is in BIP-32 only; BIP-44/49/
  84 inherit by composition, not by importing
  helpers.

## 6. Consumers

End users running personal wallets;
.B lightning
for on-chain channel opens; cluster integrations that
need address derivation.

## 7. Build / install

`./configure && make install`. Stow-based.

## 8. Versioning

Semver. The single semver string in `VERSION` at the
repo root is the source of truth; `bin/bitcoin` reads
it at runtime and `make install` copies it to
`$DATADIR/bitcoin/version`. `tests/unit/bitcoin.bats`
is the contract; the BIP vector tests under
`tests/vectors/` are the deeper regression baseline.

To bump the version (patch / minor / major release),
follow `skills/version.md`.

## 9. Testing

Three tiers (unit / sit / pit) and three surfaces
(manual `make check-*`, pre-push hook, GitHub Actions).
The pre-push hook detects the environment: cloud
sandbox runs unit only, desktop with podman runs
unit + sit + pit. CI runs unit and posts the bats log
as a PR comment on failure so an assistant agent can
read it via the GitHub MCP tools.

Full matrix, triage workflow, and per-tier ownership
are in `skills/testing.md`.

## 10. Logging

Four levels, all written to stderr: `debug`, `info`,
`warn`, `error`. Helpers defined per-script in
`bin/bitcoin` and each `libexec/bitcoin/<plugin>` (no
shared library, per §4). Every failure branch must emit
at least one `warn` / `error` / `fatal` line that names
the condition and the offending value. See
`skills/logging.md`.

## 11. Merge discipline

A PR lands the moment CI is green. Two modes are
documented in `skills/automerging.md`:

- **Mode A** — GitHub auto-merge via
  `mcp__github__enable_pr_auto_merge`. **This is the
  current default for this repo.** *Allow auto-merge*
  is on at the repo level; every PR an agent opens
  should be marked ready-for-review and armed with
  auto-merge before the agent ends its turn.
- **Mode B** — agent subscribed via
  `mcp__github__subscribe_pr_activity`, merges on the
  green CI event. Fallback when Mode A is unavailable
  (e.g. branch-protection check that auto-merge can't
  evaluate, or a one-off PR where the author wants to
  watch CI by hand).

If CI fails, file a BUG (per §3 and `skills/bugs.md`)
— never bypass the gate or disable failing tests. See
`skills/automerging.md` for the full contract and the
list of forbidden bypasses.

## 12. Milestones

Releases are planned by version. Each future release
has a backlog file at `issues/ROADMAP-X.Y.Z.md` listing
its features and bugs. One session run lands one
complete milestone; the roadmap file is removed at
release time (git history retains it). Items move from
`issues/feature/` / `issues/bug/` to `done/` and stay
there forever. See `skills/milestones.md`.

## 13. Audits

Every observable behavior of the shipping software
must trace back to a closed feature or bug in `done/`.
A regular audit (every release, or every 30 days)
walks the surface and files backfill issues for any
gap. Audit notes live at `issues/audit/YYYY-MM-DD.md`
and are never deleted. See `skills/audit.md`.
