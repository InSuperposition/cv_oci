#!/usr/bin/env bash
# verify-image-signature.sh <ref> — verify the Tekton Chains cosign signature
# and the SLSA provenance attestation on an image ref, against the Chains
# public key.
#
# Data-gathering only: it records the two exit codes and the provenance's
# resolvedDependencies digests, then prints one JSON object. The
# chainsaw-test.yaml `assert:` tree carries the checks (verify_rc == 0,
# builder/run digest is a material, ...).
#
#   {"verify_rc":N,"attest_rc":N,"resolved_digests":["sha256:..",..]}
set -euo pipefail

# chainsaw templates `env` values, not `args` — call sites pass REF as env.
ref=${REF:-${1:?set REF (or pass <ref> as $1)}}

pub=$(mktemp)
trap 'rm -f "$pub"' EXIT
cosign public-key --key k8s://tekton-chains/signing-secrets >"$pub"

verify_rc=0
cosign verify --key "$pub" --insecure-ignore-tlog=true --allow-insecure-registry \
	"$ref" >/dev/null 2>&1 || verify_rc=$?

attest_rc=0
predicate=$(cosign verify-attestation --key "$pub" --insecure-ignore-tlog=true \
	--allow-insecure-registry --type slsaprovenance1 "$ref" 2>/dev/null) || attest_rc=$?

resolved='[]'
if [ "$attest_rc" -eq 0 ]; then
	resolved=$(printf '%s' "$predicate" | jq -r '.payload' | base64 -d \
		| jq -c '[.predicate.buildDefinition.resolvedDependencies[].digest.sha256]')
fi

jq -nc \
	--argjson verify_rc "$verify_rc" \
	--argjson attest_rc "$attest_rc" \
	--argjson resolved "$resolved" \
	'{verify_rc: $verify_rc, attest_rc: $attest_rc, resolved_digests: $resolved}'
