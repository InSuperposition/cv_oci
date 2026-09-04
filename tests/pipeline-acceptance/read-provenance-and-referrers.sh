#!/usr/bin/env bash
# read-provenance-and-referrers.sh — Slice 4: verify the build image's Chains
# signature + SLSA attestation, extract the provenance materials, and list the
# referrer artifactTypes on the image.
#
#   NS   namespace of the PipelineRun `run`
#
#   {"verify_rc":0,"attest_rc":0,
#    "resolved_digests":["<64hex>",..],       # SLSA .digest.sha256 = bare hex
#    "expected_builder":"<64hex>",             # CNBBUILDER minus the sha256: prefix
#    "referrer_types":["application/vnd.dev.sigstore.bundle.v0.3+json",..]}
#
# The chainsaw assert: tree checks verify_rc/attest_rc == 0, expected_builder is
# in resolved_digests, and the sigstore-bundle / cyclonedx / cve-verdict
# referrer types are all present.
set -euo pipefail

: "${NS:?set NS}"
_here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/_resources/lib.sh
. "$_here/../_resources/lib.sh"
cd "$(cv_repo_root)"
# shellcheck source=/dev/null
. ./digests.env
zot=$(cv_zot)

digest=$(kubectl -n "$NS" get pipelinerun run \
	-o jsonpath='{.status.results[?(@.name=="app-image-digest")].value}')
ref="${zot}/${NS}@${digest}"

pub=$(mktemp)
trap 'rm -f "$pub"' EXIT
cv_chains_pubkey "$pub"

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

types=$(oras discover --insecure --format json "$ref" \
	| jq -c '[.manifests[].artifactType] | unique')

jq -nc \
	--argjson verify_rc "$verify_rc" \
	--argjson attest_rc "$attest_rc" \
	--argjson resolved "$resolved" \
	--arg builder "${CNBBUILDER#sha256:}" \
	--argjson types "$types" \
	'{verify_rc:$verify_rc, attest_rc:$attest_rc, resolved_digests:$resolved,
	  expected_builder:$builder, referrer_types:$types}'
