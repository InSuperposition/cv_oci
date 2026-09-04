#!/usr/bin/env bats
# Tests for tests/_resources/seed-pipeline-rbac.sh — the imperative RBAC seed
# for build-is-reproducible's second namespace. PATH-stubbed: asserts exactly
# which kubectl calls are made, including the NEGATIVE that cv-deploy-sa gets
# no RoleBinding (regression guard for the cv-deploy-role retirement).
#
# kubectl invocation shapes this suite relies on:
#   -n NS create serviceaccount <name>
#   -n NS patch serviceaccount <name> -p <json>
#   -n NS create rolebinding <name> --clusterrole <role> --serviceaccount NS:<sa>

load ../_resources/stub-helpers

setup() {
	ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	cd "$ROOT"
	SCRIPT=tests/_resources/seed-pipeline-rbac.sh
	stub_init
	stub kubectl 'echo -n'
}

teardown() { rm -rf "$STUB_BIN"; }

@test "requires NS" {
	run env -u NS bash "$SCRIPT"
	[ "$status" -ne 0 ]
}

@test "seeds exactly 3 ServiceAccounts, 2 automount patches, 1 RoleBinding" {
	NS=chainsaw-abc-b run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	all=$(stub_calls kubectl | jq -sc .)

	sa_creates=$(echo "$all" | jq '[.[] | select(.args[2]=="create" and .args[3]=="serviceaccount")] | length')
	[ "$sa_creates" = 3 ]

	patches=$(echo "$all" | jq '[.[] | select(.args[2]=="patch" and .args[3]=="serviceaccount")] | length')
	[ "$patches" = 2 ]

	rolebinding_creates=$(echo "$all" | jq '[.[] | select(.args[2]=="create" and .args[3]=="rolebinding")] | length')
	[ "$rolebinding_creates" = 1 ]
}

@test "the one RoleBinding is cv-smoke-rolebinding -> cv-smoke-role, not cv-deploy" {
	NS=chainsaw-abc-b run bash "$SCRIPT"
	rb=$(stub_calls kubectl | jq -sc '[.[] | select(.args[3]=="rolebinding")][0].args')
	echo "$rb" | jq -e 'contains(["cv-smoke-rolebinding","--clusterrole","cv-smoke-role"])' >/dev/null
	# negative — cv-deploy-role / cv-deploy-rolebinding never appear anywhere
	! stub_calls kubectl | grep -q 'cv-deploy-role\|cv-deploy-rolebinding'
}

@test "both cv-build-sa and cv-deploy-sa get automountServiceAccountToken:false" {
	NS=chainsaw-abc-b run bash "$SCRIPT"
	patched=$(stub_calls kubectl | jq -sc '[.[] | select(.args[2]=="patch" and .args[3]=="serviceaccount") | .args[4]]')
	[ "$patched" = '["cv-build-sa","cv-deploy-sa"]' ]
}

@test "prints {namespace,serviceaccounts:3,rolebindings:1}" {
	NS=chainsaw-abc-b run bash "$SCRIPT"
	[ "$output" = '{"namespace":"chainsaw-abc-b","serviceaccounts":3,"rolebindings":1}' ]
}
