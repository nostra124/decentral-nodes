# Roadmap — 1.22.0 (minor)

`bitcoin daemon` learns to **install** and **run** Bitcoin Core
itself, not just wrap an already-installed `bitcoind`. Three pieces
land in this milestone:

1. **FEAT-034 — `daemon enable` / `disable`**: install + load a
   `bitcoind` service in **user** mode (`systemctl --user` on Linux,
   `launchctl bootstrap gui/$UID` on macOS) or **system** mode
   (`systemctl`, `launchctl bootstrap system`). Ships unit-file
   templates at `share/bitcoin/units/bitcoind.{service,plist}` that
   the verb renders at enable time.
2. **FEAT-033 — `daemon install`**: install Bitcoin Core via the
   platform's preferred mechanism. Sub-sources: `brew`, `macports`,
   `apt`, `apk`, `source`, and `rpk` (a separate `nostra124/bitcoind`
   rpk package — see `docs/rpk-bitcoind.md`). Auto-detect default per
   platform; `--from <source>` overrides.
3. **BUG-015 close**: the existing `libexec/bitcoin/daemon` plugin
   gets the (c) treatment from its fix plan — its `start` / `stop` /
   `monitor` / `space` verbs are folded into the new daemon
   abstraction with documentation and bats coverage.

Three PRs, smallest-first:

| PR | Contains | Notes |
|---|---|---|
| 1 | FEAT-034 templates + `daemon enable / disable` | Unit-file assets first; pure-asset PR is the easiest to review. |
| 2 | FEAT-033 `daemon install` | Wraps each source as a dispatch branch; `--from rpk` is a stub-with-clear-error until the rpk repo exists. |
| 3 | BUG-015 close | Fold the legacy verbs into the new structure; bats coverage; flip BUG-015 to closed. |

Depends on:
- Nothing inside this repo. Touches new code paths only; doesn't
  change the existing `wallet` / `psbt` / `descriptor` surface.

Out of scope (future roadmaps):
- The `nostra124/bitcoind` rpk repo itself — sketched in
  `docs/rpk-bitcoind.md`, built in its own session.
- `daemon configure` (write `bitcoin.conf`) and `daemon prune` —
  ROADMAP-1.23.0+.
- Lightning service management — `lightning`'s problem, not
  `bitcoin`'s (per CLAUDE.md §1).
- Windows support — not in any current scope.

## Release gate

- `bitcoin daemon enable --user` on a Linux host with `systemctl
  --user` available, and on a macOS host with `launchctl`, brings
  bitcoind up under the invoking user; `disable` symmetrically
  brings it down. Idempotent.
- `bitcoin daemon enable --system` does the same as root, dropping
  privilege to a dedicated `bitcoin` system user inside the unit.
- `bitcoin daemon install --from brew` (macOS) and `--from apt`
  (Debian/Ubuntu) install Bitcoin Core's `bitcoind` binary into
  PATH from a clean host.
- `bitcoin daemon install --from source` clones, builds, and
  installs Bitcoin Core from `github.com/bitcoin/bitcoin` against
  the `--tag <v>` argument (default: latest stable release tag).
- `bitcoin daemon install --from rpk` errors with a clear "not yet
  shipped; see docs/rpk-bitcoind.md" message — placeholder until
  the rpk repo lands.
- BUG-015 closes with the legacy plugin's verbs folded into the
  new abstraction and bats coverage on all four.
- Pre-push hook + CI green on each milestone PR.
