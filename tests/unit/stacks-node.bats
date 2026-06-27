#!/usr/bin/env bats
#
# Unit contract for stacks-node (FEAT-314). Shared assertions live in
# tests/unit/lib/node_contract.bash.

load lib/node_contract

setup() { node_contract_setup; }

@test "stacks-node: help resolves and prints usage" { nc_assert_help stacks-node; }

@test "stacks-node: unknown verb fails naming the verb" { nc_assert_unknown_verb stacks-node; }

@test "stacks-node: registered in PACKAGES + .rpk COMMANDS" { nc_assert_registered stacks-node; }

@test "stacks-node: no forbidden sibling calls (FEAT-195)" { nc_assert_no_forbidden_siblings stacks-node; }

@test "stacks-node: version equals the package VERSION" { nc_assert_version stacks-node; }
