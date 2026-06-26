# Roadmap — 3.5.0 (minor)

**Self-hosting nodes & infrastructure.** A set of Tier 3 nodes that turn
the stack into a self-hostable services toolkit — a Git forge with CI, a
system-admin UI, and a per-user web UI — plus the CI infrastructure that
lets the container test tiers run in cloud sessions.

> **Backfill note.** These features were built and merged ahead of a
> formal release (the audit in CLAUDE.md §13 flagged that they shipped
> without tracking issues). This roadmap and the FEAT files below were
> written retroactively so every shipping behaviour traces to a closed
> issue in `done/`. `VERSION` is still `3.3.2`; bumping it to cut the
> 3.5.0 release is the remaining packaging step (see
> `skills/version.md`). The atomic-swap work (FEAT-306) was shifted to
> 3.6.0 to give these shipped features the 3.5.0 slot.

---

## FEAT-309 — permanent podman in web sessions ✅ DONE
**File:** `issues/feature/done/309-podman-permanent-web-sessions.md`
A `SessionStart` hook installs podman on every Claude Code on the web
session (idempotent, remote-only, synchronous) so the SIT/PIT container
tiers and `.githooks/pre-push` can actually run a checkout. (PR #124)

## FEAT-310 — forgejo-node: Forgejo forge + per-platform CI runners ✅ DONE
**File:** `issues/feature/done/310-forgejo-node.md`
Install/operate the Forgejo server, and set up Forgejo Actions runners by
platform (docker/lxc/host + macOS/Windows host presets). Includes
`contrib/Install-ForgejoRunner.ps1` for native Windows runner setup.
(PR #124 + #125)

## FEAT-311 — webmin-node: web system administration ✅ DONE
**File:** `issues/feature/done/311-webmin-node.md`
Install/operate Webmin (root admin UI, HTTPS :10000) from the official
signed repo via the systemd `webmin` unit. (PR #128)

## FEAT-312 — usermin-node: per-user web interface ✅ DONE
**File:** `issues/feature/done/312-usermin-node.md`
Install/operate Usermin (Webmin's per-user sibling, HTTPS :20000) from
the same repo via the systemd `usermin` unit. (PR #128)

---

## Recommended order (as shipped)

```
FEAT-309   podman hook — unblocks the container test tiers first
FEAT-310   forgejo-node — forge + CI runners (+ Windows installer)
FEAT-311   webmin-node — root admin UI
FEAT-312   usermin-node — per-user UI (sibling of webmin-node)
```

## Release gate

- All four nodes' bats suites green in `bats tests/unit/*.bats`
  (`forgejo-node` + `webmin-node` + `usermin-node`), and `make install`
  stages each tree.
- The podman hook installs cleanly and is idempotent on a fresh web
  session.
- `VERSION` bumped to `3.5.0` per `skills/version.md` to cut the release,
  after which this file is removed (git history retains it) and the FEAT
  files remain in `done/`.
