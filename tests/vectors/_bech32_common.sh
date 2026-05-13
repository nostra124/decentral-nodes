# Shared bech32 vectors for tests/vectors/bip-0173.t and bip-0350.t.
#
# Not a TAP test file: prove only picks up *.t. This file is sourced
# by the two .t files that share the same set of valid/invalid bech32
# strings, so adding or correcting a vector is a one-edit change
# (FEAT-024).

declare -a BECH32_VALID=(
	A12UEL5L
	a12uel5l
	an83characterlonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1tt5tgs
	abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw
	11qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqc8247j
	split1checkupstagehandshakeupstreamerranterredcaperred2y9e3w
	?1ezyfcl
)

# The "basic" invalid set — overall-length / no-separator / empty-HRP
# / invalid-char / short-checksum / case-mismatch-of-HRP / empty-HRP
# variants. bip-0350.t adds extra entries with binary characters in
# its own array.
declare -a BECH32_INVALID_BASIC=(
	an84characterslonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1569pvx
	pzry9x0s0muk
	1pzry9x0s0muk
	x1b4n0q5v
	li1dgmt3
	A1G7SGD8
	10a06t8
	1qzzfhee
)

# vi: ft=bash
