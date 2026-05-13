#!/usr/bin/env bash

. bitcoin.sh
# FEAT-024: shared vectors live in _bech32_common.sh (single source
# of truth across bip-0173.t and bip-0350.t).
. "$(dirname "$BASH_SOURCE")/_bech32_common.sh"

declare -a correct_bech32=( "${BECH32_VALID[@]}" )
declare -a incorrect_bech32=( "${BECH32_INVALID_BASIC[@]}" )

declare -A correct_segwit_addresses=(
  [BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4]=0014751e76e8199196d454941c45d1b3a323f1433bd6
  [tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7]=00201863143c14c5166804bd19203356da136c985678cd4d27a1b8c6329604903262
  [bc1pw508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7k7grplx]=5128751e76e8199196d454941c45d1b3a323f1433bd6751e76e8199196d454941c45d1b3a323f1433bd6
  [BC1SW50QA3JX3S]=6002751e
  [bc1zw508d6qejxtdg4y5r3zarvaryvg6kdaj]=5210751e76e8199196d454941c45d1b3a323
  [tb1qqqqqp399et2xygdj5xreqhjjvcmzhxw4aywxecjdzew6hylgvsesrxh6hy]=0020000000c4a5cad46221b2a187905e5266362b99d5e91c6ce24d165dab93e86433
)

declare -a incorrect_segwit_addresses=(
   tc1qw508d6qejxtdg4y5r3zarvary0c5xw7kg3g4ty
   bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5
   BC13W508D6QEJXTDG4Y5R3ZARVARY0C5XW7KN40WF2
   bc1rw5uspcuh
   bc10w508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7kw5rljs90
   BC1QR508D6QEJXTDG4Y5R3ZARVARYV98GJ9P
   tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sL5k7
   bc1zw508d6qejxtdg4y5r3zarvaryvqyzf3du
   tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3pjxtptv
   bc1gmk9yu
)

echo 1..$((
  ${#correct_bech32[@]}
+ ${#incorrect_bech32[@]}
+ ${#correct_segwit_addresses[@]}
+ ${#incorrect_segwit_addresses[@]}
))
declare -i t=0
for v in "${correct_bech32[@]}"
do
  ((t++))
  if bech32_decode "$v" >/dev/null
  then echo "ok $t - true positive for '$v'" 
  else echo "not ok $t - false negative for '$v'" 
  fi
done

for v in "${incorrect_bech32[@]}"
do
  ((t++))
  if ! bech32_decode "$v" >/dev/null
  then echo "ok $t - true negative for '$v'" 
  else echo "not ok $t - false positive for '$v'" 
  fi
done

for k in "${!correct_segwit_addresses[@]}"
do
  ((t++))
  if bech32_decode "$k" >/dev/null
  then echo "ok $t - $k is a valid bech32"
  else echo "not ok $t - $k should not have been parsed as valid"
  fi
done

for v in "${incorrect_segwit_addresses[@]}"
do
  ((t++))
  if ! segwit_verify "$v"
  then echo "ok $t - true negative for '$v'" 
  else echo "not ok $t - false positive for '$v'" 
  fi
done

# vi: ft=bash
