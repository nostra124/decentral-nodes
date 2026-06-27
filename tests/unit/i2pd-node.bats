#!/usr/bin/env bats
#
# Unit contract for i2pd-node (FEAT-314). Shared assertions live in
# tests/unit/lib/node_contract.bash.

load lib/node_contract

setup() { node_contract_setup; }

@test "i2pd-node: help resolves and prints usage" { nc_assert_help i2pd-node; }

@test "i2pd-node: unknown verb fails naming the verb" { nc_assert_unknown_verb i2pd-node; }

@test "i2pd-node: registered in PACKAGES + .rpk COMMANDS" { nc_assert_registered i2pd-node; }

@test "i2pd-node: no forbidden sibling calls (FEAT-195)" { nc_assert_no_forbidden_siblings i2pd-node; }
