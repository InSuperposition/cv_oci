#!/usr/bin/env bats
# Tests for tests/_resources/fetch-artifact-referrers.sh — the oras-discover
# poll loop. PATH-stubbed oras. POLL_INTERVAL_SECONDS=0 keeps the not-yet-signed
# case fast (a real chainsaw run keeps the script's default 10s poll).

load ../_resources/stub-helpers

setup() {
	ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	cd "$ROOT"
	SCRIPT=tests/_resources/fetch-artifact-referrers.sh
	stub_init
}

teardown() { rm -rf "$STUB_BIN"; }

@test "requires REF" {
	run env -u REF bash "$SCRIPT"
	[ "$status" -ne 0 ]
}

@test "already signed on the first poll: signed=true, no retry" {
	stub oras "echo '{\"manifests\":[{\"artifactType\":\"application/vnd.dev.sigstore.bundle.v0.3+json\"},{\"artifactType\":\"application/vnd.cyclonedx+json\"}]}'"
	REF=zot.example:5000/cv@sha256:abc run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	echo "$output" | jq -e '.signed == true' >/dev/null
	echo "$output" | jq -e '.referrer_types | contains(["application/vnd.dev.sigstore.bundle.v0.3+json"])' >/dev/null
	calls=$(stub_calls oras | wc -l | tr -d ' ')
	[ "$calls" = 1 ]
}

@test "never signed within the deadline: signed=false, does not fail" {
	stub oras "echo '{\"manifests\":[{\"artifactType\":\"application/vnd.cyclonedx+json\"}]}'"
	run env REF=zot.example:5000/cv@sha256:abc DEADLINE_SECONDS=1 POLL_INTERVAL_SECONDS=0 bash "$SCRIPT"
	[ "$status" -eq 0 ]
	echo "$output" | jq -e '.signed == false' >/dev/null
}

@test "calls oras discover --insecure --format json with the ref" {
	# signed on the first call, so the loop exits after exactly one poll —
	# no deadline override needed.
	stub oras "echo '{\"manifests\":[{\"artifactType\":\"application/vnd.dev.sigstore.bundle.v0.3+json\"}]}'"
	REF=zot.example:5000/cv@sha256:abc run bash "$SCRIPT"
	args=$(stub_call_args oras 0)
	[ "$args" = '["discover","--insecure","--format","json","zot.example:5000/cv@sha256:abc"]' ]
}
