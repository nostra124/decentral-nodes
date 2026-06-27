#!/usr/bin/env bats
#
# Unit contract for ipfs-node (FEAT-314). Shared assertions live in
# tests/unit/lib/node_contract.bash.

load lib/node_contract

setup() { node_contract_setup; }

@test "ipfs-node: help resolves and prints usage" { nc_assert_help ipfs-node; }

@test "ipfs-node: unknown verb fails naming the verb" { nc_assert_unknown_verb ipfs-node; }

@test "ipfs-node: registered in PACKAGES + .rpk COMMANDS" { nc_assert_registered ipfs-node; }

@test "ipfs-node: no forbidden sibling calls (FEAT-195)" { nc_assert_no_forbidden_siblings ipfs-node; }
