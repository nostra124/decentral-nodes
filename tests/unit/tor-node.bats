#!/usr/bin/env bats
#
# Unit contract for tor-node (FEAT-314). Shared assertions live in
# tests/unit/lib/node_contract.bash.

load lib/node_contract

setup() { node_contract_setup; }

@test "tor-node: help resolves and prints usage" { nc_assert_help tor-node; }

@test "tor-node: unknown verb fails naming the verb" { nc_assert_unknown_verb tor-node; }

@test "tor-node: registered in PACKAGES + .rpk COMMANDS" { nc_assert_registered tor-node; }

@test "tor-node: no forbidden sibling calls (FEAT-195)" { nc_assert_no_forbidden_siblings tor-node; }
