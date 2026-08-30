#!/usr/bin/env bats
# Tests for assert-frontend-contract.sh and assert-release-tree.sh.

setup() {
	ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	FE="$BATS_TEST_TMPDIR/fe"
	RT="$BATS_TEST_TMPDIR/rt"
	mkfe "$FE"
	mkrt "$RT"
}

# A minimal cv_frontend checkout that satisfies the contract.
mkfe() {
	local d="$1"
	mkdir -p "$d/app" "$d/public"
	: > "$d/server.ts"; : > "$d/tsconfig.json"; : > "$d/package-lock.json"
	: > "$d/app/router.ts"; : > "$d/app/routes.ts"; : > "$d/app/assets.ts"
	cat > "$d/package.json" <<-'EOF'
		{ "type": "module",
		  "scripts": { "start": "x", "test": "x", "typecheck": "x" },
		  "dependencies": { "remix": "^3.0.0-beta.10" } }
	EOF
}

# A minimal release tree that passes assert-release-tree.sh (floor lowered).
mkrt() {
	local d="$1"
	mkdir -p "$d/app" "$d/node_modules/remix" "$d/node_modules/.bin"
	: > "$d/server.ts"; : > "$d/tsconfig.json"; : > "$d/package.json"
	: > "$d/app/router.ts"
	dd if=/dev/zero of="$d/node_modules/remix/bulk" bs=1m count=2 status=none
}

fe() { RELEASE_TREE_FLOOR_MB=1 run "$ROOT/scripts/assert-frontend-contract.sh" "$@"; }
rt() { RELEASE_TREE_FLOOR_MB=1 run "$ROOT/scripts/assert-release-tree.sh" "$@"; }

@test "contract: a well-formed checkout passes" {
	fe "$FE"; [ "$status" -eq 0 ]
}

@test "contract: missing server.ts fails" {
	rm "$FE/server.ts"; fe "$FE"
	[ "$status" -ne 0 ]; [[ "$output" == *"server.ts"* ]]
}

@test "contract: package.json .type != module fails" {
	echo '{"type":"commonjs","scripts":{"start":"x","test":"x","typecheck":"x"},"dependencies":{"remix":"x"}}' > "$FE/package.json"
	fe "$FE"; [ "$status" -ne 0 ]
}

@test "contract: missing test script fails" {
	echo '{"type":"module","scripts":{"start":"x","typecheck":"x"},"dependencies":{"remix":"x"}}' > "$FE/package.json"
	fe "$FE"; [ "$status" -ne 0 ]
}

@test "release tree: a well-formed tree passes" {
	rt "$RT"; [ "$status" -eq 0 ]
}

@test "release tree: missing entrypoint fails" {
	rm "$RT/server.ts"; rt "$RT"
	[ "$status" -ne 0 ]; [[ "$output" == *"server.ts"* ]]
}

@test "release tree: bundled typescript fails" {
	mkdir -p "$RT/node_modules/typescript"; rt "$RT"
	[ "$status" -ne 0 ]; [[ "$output" == *"typescript"* ]]
}

@test "release tree: a *.test.* file fails" {
	: > "$RT/app/thing.test.ts"; rt "$RT"
	[ "$status" -ne 0 ]; [[ "$output" == *"test"* ]]
}

@test "release tree: below the size floor fails" {
	rm "$RT/node_modules/remix/bulk"
	RELEASE_TREE_FLOOR_MB=50 run "$ROOT/scripts/assert-release-tree.sh" "$RT"
	[ "$status" -ne 0 ]; [[ "$output" == *"floor"* ]]
}

@test "release tree: df preflight fails when MIN_FREE_MB is impossibly high" {
	MIN_FREE_MB=999999999 RELEASE_TREE_FLOOR_MB=1 run "$ROOT/scripts/assert-release-tree.sh" "$RT"
	[ "$status" -ne 0 ]; [[ "$output" == *"free"* ]]
}
