#!/usr/bin/env bats
# Tests for tests/_resources/wait-for-pipelinerun.sh — the fail-fast poll.
# PATH-stubbed kubectl. Every case that doesn't resolve on the first poll sets
# DEADLINE_SECONDS + POLL_INTERVAL_SECONDS short so the test stays fast — a
# real chainsaw run keeps the script's defaults (1400s / 10s).

load ../_resources/stub-helpers

setup() {
	ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	cd "$ROOT"
	SCRIPT=tests/_resources/wait-for-pipelinerun.sh
	stub_init
}

teardown() { rm -rf "$STUB_BIN"; }

@test "requires NAME" {
	run env -u NAME NS=ns bash "$SCRIPT"
	[ "$status" -ne 0 ]
}

@test "requires NS" {
	run env -u NS NAME=run bash "$SCRIPT"
	[ "$status" -ne 0 ]
}

@test "Succeeded=True on the first poll: exit 0, prints the JSON result" {
	stub kubectl 'echo True'
	run env NAME=run NS=chainsaw-abc bash "$SCRIPT"
	[ "$status" -eq 0 ]
	[ "$output" = '{"name":"run","namespace":"chainsaw-abc","succeeded":true}' ]
}

@test "Succeeded=False: exit 1, the condition message goes to stderr" {
	# First call (status jsonpath) returns False; the second call (message
	# jsonpath) is a distinct kubectl invocation the script makes to fetch and
	# print the message — same stub, keyed on which jsonpath was requested.
	stub kubectl "
case \"\$*\" in
  *'.status.conditions[0].status'*) echo False ;;
  *'.status.conditions[0].message'*) echo 'image pull failed' ;;
esac
"
	run env NAME=run NS=chainsaw-abc bash "$SCRIPT"
	[ "$status" -eq 1 ]
	[[ "$output" == *"image pull failed"* ]]
}

@test "never resolves within the deadline: exit 1" {
	stub kubectl 'echo Unknown'
	run env NAME=run NS=chainsaw-abc DEADLINE_SECONDS=1 POLL_INTERVAL_SECONDS=0 bash "$SCRIPT"
	[ "$status" -eq 1 ]
	[[ "$output" == *"did not finish within the deadline"* ]]
}

@test "polls the exact PipelineRun by name and namespace" {
	stub kubectl 'echo True'
	run env NAME=run NS=chainsaw-abc bash "$SCRIPT"
	args=$(stub_call_args kubectl 0)
	[ "$args" = '["-n","chainsaw-abc","get","pipelinerun","run","-o","jsonpath={.status.conditions[0].status}"]' ]
}
