#!/usr/bin/env bats
#
# Unit contract for liquid-node (FEAT-314). Shared assertions live in
# tests/unit/lib/node_contract.bash.

load lib/node_contract

setup() { node_contract_setup; }

@test "liquid-node: help resolves and prints usage" { nc_assert_help liquid-node; }

@test "liquid-node: unknown verb fails naming the verb" { nc_assert_unknown_verb liquid-node; }

@test "liquid-node: registered in PACKAGES + .rpk COMMANDS" { nc_assert_registered liquid-node; }

@test "liquid-node: no forbidden sibling calls (FEAT-195)" { nc_assert_no_forbidden_siblings liquid-node; }

@test "liquid-node: version equals the package VERSION" { nc_assert_version liquid-node; }
