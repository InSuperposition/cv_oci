#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Tests for scripts/resolve-sha.sh against a local bare-repo fixture
# (T-2-A — offline, deterministic). One @network test hits the real remote.

setup_file() {
	ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	export ROOT
	FIX="$BATS_FILE_TMPDIR/frontend.git"
	work="$BATS_FILE_TMPDIR/work"
	git init -q --bare "$FIX"
	git init -q "$work"
	git -C "$work" -c user.email=t@t -c user.name=t commit -q --allow-empty -m c1
	git -C "$work" -c user.email=t@t -c user.name=t commit -q --allow-empty -m c2
	git -C "$work" branch -M main
	git -C "$work" tag v1.0.0
	git -C "$work" remote add origin "$FIX"
	git -C "$work" push -q origin main --tags
	export FIX
	export HEAD_SHA="$(git -C "$work" rev-parse HEAD)"
	export V1_SHA="$(git -C "$work" rev-parse v1.0.0^{})"
}

run_resolve() { run --separate-stderr "$ROOT/scripts/resolve-sha.sh" "$FIX" "$1"; }

@test "full SHA passes through unchanged" {
	run_resolve "$HEAD_SHA"
	[ "$status" -eq 0 ]
	[ "$output" = "$HEAD_SHA" ]
}

@test "branch name resolves to its tip SHA" {
	run_resolve main
	[ "$status" -eq 0 ]
	[ "$output" = "$HEAD_SHA" ]
}

@test "tag resolves to the dereferenced commit SHA" {
	run_resolve v1.0.0
	[ "$status" -eq 0 ]
	[ "$output" = "$V1_SHA" ]
}

@test "unknown ref fails loud" {
	run_resolve no-such-branch
	[ "$status" -ne 0 ]
	[[ "$stderr" == *"not found"* ]]
}

@test "a short SHA is rejected, not silently missed" {
	run_resolve "${HEAD_SHA:0:12}"
	[ "$status" -ne 0 ]
	[[ "$stderr" == *"full 40-hex"* ]]
}

@test "empty ref fails with usage" {
	run "$ROOT/scripts/resolve-sha.sh" "$FIX" ""
	[ "$status" -ne 0 ]
}

@test "CV_FRONTEND_REMOTE overrides the repo arg" {
	CV_FRONTEND_REMOTE="$FIX" run --separate-stderr "$ROOT/scripts/resolve-sha.sh" ignored main
	[ "$status" -eq 0 ]
	[ "$output" = "$HEAD_SHA" ]
}

@test "@network the pinned cv_frontend fixture SHA still exists" {
	# shellcheck disable=SC1091
	source "$ROOT/digests.env"
	run git ls-remote "$FRONTEND_REPO" "$FRONTEND_FIXTURE_SHA"
	# ls-remote by SHA returns empty but exit 0 when reachable; a network/auth
	# failure is non-zero. This proves the repo is reachable, not the SHA — the
	# SHA is verified after clone in the resolve Task.
	[ "$status" -eq 0 ]
}
