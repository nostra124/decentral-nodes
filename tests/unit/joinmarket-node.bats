#!/usr/bin/env bats
#
# Unit contract for joinmarket-node (FEAT-314). Shared assertions live in
# tests/unit/lib/node_contract.bash.

load lib/node_contract

setup() { node_contract_setup; }

@test "joinmarket-node: help resolves and prints usage" { nc_assert_help joinmarket-node; }

@test "joinmarket-node: unknown verb fails naming the verb" { nc_assert_unknown_verb joinmarket-node; }

@test "joinmarket-node: registered in PACKAGES + .rpk COMMANDS" { nc_assert_registered joinmarket-node; }

@test "joinmarket-node: no forbidden sibling calls (FEAT-195)" { nc_assert_no_forbidden_siblings joinmarket-node; }
