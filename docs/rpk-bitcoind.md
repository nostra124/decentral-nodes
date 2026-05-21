# Sketch: a `bitcoind` rpk package

This is a *plan*, not built code. It outlines a separate rpk
repository — `github.com/nostra124/bitcoind` — that wraps a
Bitcoin Core build into the standard rpk shape. Once it exists,
`bitcoin daemon install --from rpk` (FEAT-033) becomes a real
backend instead of the placeholder stub.

## Why a separate repo

Per `CLAUDE.md` §4, this `bitcoin` repo's no-shared-lib policy
keeps it focused on the educational frontend (BIP plugins +
wallet surface). Carrying a full Bitcoin Core build inside this
repo would:

- Inflate the source tree by ~500MB once the Core submodule is
  vendored.
- Bind this repo's release cadence to Core's (every Core release
  would force a `bitcoin` release).
- Mix two different test surfaces (Core's gtest/functional suite
  vs. this repo's bats).

A sibling rpk package keeps the concerns separated and lets each
repo cut releases on its own schedule.

## Repo layout (proposed)

```
nostra124/bitcoind/
├── CLAUDE.md                # mirrors CLAUDE.md.foundation
├── VERSION                  # tracks Core's release versions (e.g. 27.0)
├── configure                # rpk-convention autoconf shim
├── Makefile.in              # see "build" below
├── install                  # standalone-install shim, like this repo's
├── bin/bitcoind             # the built binary (post-make)
├── bin/bitcoin-cli          # likewise
├── bin/bitcoin-tx           # likewise
├── share/doc/bitcoind/      # README + selected Core docs
├── src/                     # git submodule → github.com/bitcoin/bitcoin
└── .rpk/depends/            # boost, libdb, openssl, autoconf, …
```

## Build (in Makefile.in)

The package's `install` target is unusual for rpk in that it
builds from a submodule, not from in-repo source. Roughly:

```make
build/bitcoind: src/.git
	cd src && ./autogen.sh
	cd src && ./configure --prefix=$(PWD)/build --disable-wallet \
	                       --disable-tests --disable-bench --without-gui
	cd src && make -j$(JOBS)
	cd src && make install

install: build/bitcoind
	@mkdir -p $(BUILD_DIR)$(BINDIR) $(BUILD_DIR)$(DATADIR)/doc/bitcoind
	@cp build/bin/bitcoind   $(BUILD_DIR)$(BINDIR)/
	@cp build/bin/bitcoin-cli $(BUILD_DIR)$(BINDIR)/
	@cp build/bin/bitcoin-tx  $(BUILD_DIR)$(BINDIR)/
	@cp src/README.md         $(BUILD_DIR)$(DATADIR)/doc/bitcoind/
	@stow -d build -t $(PREFIX) bitcoind
```

The `--disable-wallet` flag is the educational mandate: the
`bitcoin` repo IS the wallet. Pairing the rpk-installed Core with
this repo's wallet keeps the two concerns cleanly separated even
in the deployed footprint.

## How this repo consumes it

In `libexec/bitcoin/daemon` (after FEAT-033 lands), the `--from
rpk` branch becomes:

```sh
daemon:install:rpk() {
    if ! command -v rpk >/dev/null; then
        error "daemon install --from rpk: rpk not installed; see https://github.com/nostra124/rpk"
        return 1
    fi
    rpk install bitcoind
    bitcoind --version
}
```

Until the rpk-bitcoind repo lands, the same branch errors with
the placeholder message documented in FEAT-033.

## Versioning

The rpk repo's `VERSION` tracks **Core's** version, not the
wrapper's: `27.0`, `28.0`, etc. A second integer can be appended
for wrapper-only fixes (`27.0-1`) but the major track follows
upstream.

## Out of scope here

- The wrapper repo itself — that's its own session of work in a
  separate repository, with its own ROADMAP-X.Y.Z.md, issue tree,
  and CI.
- Pruned-node defaults, signet/testnet defaults — those are
  configuration concerns for `bitcoin daemon configure` (a future
  ROADMAP).
- Tor / I2P support — Core supports both; the wrapper just needs
  to not strip the configure flags. No special action.
- A `bitcoind` binary for Windows — not in any current roadmap.
