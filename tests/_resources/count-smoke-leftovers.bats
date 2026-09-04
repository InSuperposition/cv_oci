#!/usr/bin/env bats
# Tests for tests/_resources/count-smoke-leftovers.sh — a thin `kubectl get`
# wrapper. PATH-stubbed per the test-double harness (TODOS.md): asserts the
# command construction, not real cluster behaviour.

load ../_resources/stub-helpers

setup() {
	ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	cd "$ROOT"
	SCRIPT=tests/_resources/count-smoke-leftovers.sh
	stub_init
}

teardown() {
	rm -rf "$STUB_BIN"
}

@test "requires NS" {
	run env -u NS bash "$SCRIPT"
	[ "$status" -ne 0 ]
}

@test "queries deploy,svc labelled cv-oci/smoke in NS" {
	stub kubectl 'echo -n'
	NS=chainsaw-abc run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	args=$(stub_call_args kubectl 0)
	[ "$args" = '["-n","chainsaw-abc","get","deploy,svc","-l","cv-oci/smoke","-o","name"]' ]
}

@test "no leftovers -> {leftovers:0}" {
	stub kubectl 'echo -n'
	NS=chainsaw-abc run bash "$SCRIPT"
	[ "$output" = '{"leftovers":0}' ]
}

@test "two leftovers -> {leftovers:2}" {
	stub kubectl 'printf "deployment.apps/smoke-x\nservice/smoke-x\n"'
	NS=chainsaw-abc run bash "$SCRIPT"
	[ "$output" = '{"leftovers":2}' ]
}
