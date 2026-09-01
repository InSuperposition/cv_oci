#!/usr/bin/env bats
# Tests the digest parser in the `results` step of tasks/buildpacks.yaml.
#
# The awk program is copied verbatim below and a guard test greps it back out
# of the Task, so the two cannot drift (same pattern as gen-digests.bats).

setup() {
	ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	cd "$ROOT"
	FIX="$ROOT/scripts/test/fixtures"
}

# --- verbatim copy of the results step's parse; keep in sync with the Task ---
parse_digest() {
	awk '
          /^\[/            { in_image = ($0 ~ /^\[image\][ \t]*$/); next }
          in_image && $1 == "digest" {
            v = $0; sub(/^[^=]*=[ \t]*/, "", v); gsub(/[" \t]/, "", v)
            print v; exit
          }
        ' "$1"
}

@test "reads digest from the [image] table" {
	run parse_digest "$FIX/report-image-only.toml"
	[ "$status" -eq 0 ]
	[ "$output" = "sha256:1111111111111111111111111111111111111111111111111111111111111111" ]
}

@test "ignores a digest in [[build.bom]] metadata that marshals before [image]" {
	run parse_digest "$FIX/report-bom-digest-first.toml"
	[ "$output" = "sha256:2222222222222222222222222222222222222222222222222222222222222222" ]
}

@test "emits nothing when [image].digest is absent (step then fails loud)" {
	run parse_digest "$FIX/report-no-digest.toml"
	[ -z "$output" ]
}

@test "the Task's results step still carries this awk program" {
	grep -qF 'in_image = ($0 ~ /^\[image\][ \t]*$/); next' tasks/buildpacks.yaml
	grep -qF 'no [image].digest in /layers/report.toml' tasks/buildpacks.yaml
}
