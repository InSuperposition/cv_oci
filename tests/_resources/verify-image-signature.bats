#!/usr/bin/env bats
# Tests for tests/_resources/verify-image-signature.sh — cosign wrapper.
# PATH-stubbed cosign; both the success and the tampered/failed-verify shape.

load ../_resources/stub-helpers

# A minimal in-toto DSSE envelope whose base64 payload decodes to a SLSA
# provenance statement naming one resolvedDependencies digest.
FIXTURE_PAYLOAD_JSON='{"predicate":{"buildDefinition":{"resolvedDependencies":[{"digest":{"sha256":"deadbeef"}}]}}}'

setup() {
	ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	cd "$ROOT"
	SCRIPT=tests/_resources/verify-image-signature.sh
	stub_init
}

teardown() { rm -rf "$STUB_BIN"; }

@test "requires REF" {
	run env -u REF bash "$SCRIPT"
	[ "$status" -ne 0 ]
}

@test "verified + attested: prints rc=0/0 and the resolved digest" {
	stub cosign "
case \"\$1\" in
  public-key) echo fake-pubkey ;;
  verify) exit 0 ;;
  verify-attestation)
    payload=\$(printf '%s' '$FIXTURE_PAYLOAD_JSON' | base64)
    jq -nc --arg p \"\$payload\" '{payload: \$p}'
    ;;
esac
"
	REF=zot.example:5000/cv@sha256:abc run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	echo "$output" | jq -e '.verify_rc == 0 and .attest_rc == 0' >/dev/null
	echo "$output" | jq -e '.resolved_digests == ["deadbeef"]' >/dev/null
}

@test "verify fails (tampered image): verify_rc != 0" {
	stub cosign "
case \"\$1\" in
  public-key) echo fake-pubkey ;;
  verify) exit 1 ;;
  verify-attestation) exit 1 ;;
esac
"
	REF=zot.example:5000/cv@sha256:tampered run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	echo "$output" | jq -e '.verify_rc != 0 and .attest_rc != 0' >/dev/null
	echo "$output" | jq -e '.resolved_digests == []' >/dev/null
}

@test "calls cosign verify with --insecure-ignore-tlog and the ref" {
	stub cosign "
case \"\$1\" in
  public-key) echo fake-pubkey ;;
  verify) exit 0 ;;
  verify-attestation) exit 1 ;;
esac
"
	REF=zot.example:5000/cv@sha256:abc run bash "$SCRIPT"
	verify_args=$(stub_calls cosign | jq -sc '[.[] | select(.args[0]=="verify")][0].args')
	echo "$verify_args" | jq -e 'contains(["--insecure-ignore-tlog=true","zot.example:5000/cv@sha256:abc"])' >/dev/null
}
