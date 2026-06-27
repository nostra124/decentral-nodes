#!/usr/bin/env bats
#
# Unit contract for storj-node (FEAT-314). Shared assertions live in
# tests/unit/lib/node_contract.bash.

load lib/node_contract

setup() { node_contract_setup; }

@test "storj-node: help resolves and prints usage" { nc_assert_help storj-node; }

@test "storj-node: unknown verb fails naming the verb" { nc_assert_unknown_verb storj-node; }

@test "storj-node: registered in PACKAGES + .rpk COMMANDS" { nc_assert_registered storj-node; }

@test "storj-node: no forbidden sibling calls (FEAT-195)" { nc_assert_no_forbidden_siblings storj-node; }
