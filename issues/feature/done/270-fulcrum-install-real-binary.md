---
id: FEAT-270
type: feature
priority: medium
status: open
---

# `fulcrum install` actually installs Fulcrum (prebuilt release / source build)

## Motivation

`fulcrum install` could not install a usable Fulcrum binary: `--from
brew`/`apt` referenced packages that don't exist, and `--from source`
just printed "build it yourself" and errored. So `fulcrum enable`
always failed its runnable preflight (no real Fulcrum on PATH — the
`Fulcrum` name even collided with this repo's own dispatcher). bitcoin
(`daemon install`) and lightning (`install-core`) install their
binaries; fulcrum should too.

## Reality of Fulcrum distribution

Fulcrum (cculianu/Fulcrum) ships, per GitHub release (v2.1.1):
prebuilt **Linux** binaries (`arm64`/`x86_64`), Windows, a Docker
image, and source — **no macOS binary**. So Linux can download a
prebuilt; macOS must build from source (C++/Qt5 + rocksdb).

## Behavior

`fulcrum install [--from release|source|docker] [--tag <v>] [--prefix
<path>]`, default chosen by host (Linux → `release`, macOS → `source`):

- **release** — fetch the matching prebuilt asset
  (`Fulcrum-<ver>-<arch>-linux.tar.gz`) from the GitHub release,
  **SHA256-verify** it against the release `shasums.txt`, extract, and
  `install -m 0755` `Fulcrum` + `FulcrumAdmin` into `<prefix>/bin`
  (default `/usr/local`, a world-readable path a service account can
  run — feeding the FEAT-267 runnable model). Refuses on non-Linux.
- **source** — clone + `qmake Fulcrum.pro && make` (needs Qt5 +
  rocksdb dev libs; errors with the dependency hint if `qmake` is
  absent). Works on macOS.
- **docker** — `docker pull cculianu/fulcrum`.

`$FULCRUM_RELEASE_API` / `$FULCRUM_SOURCE_REPO` override the endpoints
for the test harness.

## Acceptance Criteria

1. `install --from release` downloads the right asset, verifies its
   SHA256, and installs `Fulcrum` into `<prefix>/bin`. Proven by
   `tests/unit/fulcrum.bats` FEAT-270 (fully mocked curl/uname/sudo).
2. `install --from release` refuses on a non-Linux host with a pointer
   to `--from source`. Proven by FEAT-270.
3. `install --from source` errors with a Qt5 hint when `qmake` is
   absent.
4. `install help` lists `release`, `source`, `docker`; unknown sources
   still error. Proven by FEAT-270 + the existing FEAT-056 AC6 test.
5. After a real `install`, `fulcrum enable` finds a runnable binary
   (resolves the FEAT-267 preflight that previously refused).
