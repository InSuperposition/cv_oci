#!/usr/bin/env bash
# verify-signature-and-referrers.sh — Slice 4: the build image signature and
# SLSA attestation verify against the Chains key; the provenance names the
# builder digest as a material; the sigstore-bundle + CycloneDX SBOM +
# cve-verdict referrers are all present on the image.
#
#   NS   namespace of the PipelineRun `run`
#
# T5a: asserts in-script. T5b: split into ../_resources/verify-image-signature.sh
# (rc + resolved digests) + a referrer-type list + assert: trees.
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

cosign verify --key "$pub" --insecure-ignore-tlog=true --allow-insecure-registry "$ref" >/dev/null
cosign verify-attestation --key "$pub" --insecure-ignore-tlog=true --allow-insecure-registry \
	--type slsaprovenance1 "$ref" >/dev/null

pred=$(cosign verify-attestation --key "$pub" --insecure-ignore-tlog=true --allow-insecure-registry \
	--type slsaprovenance1 "$ref" 2>/dev/null | jq -r '.payload' | base64 -d)
printf '%s' "$pred" | jq -e \
	".predicate.buildDefinition.resolvedDependencies[]|select(.digest.sha256==\"${CNBBUILDER#sha256:}\")" >/dev/null

refs=$(oras discover --insecure --format tree "$ref")
printf '%s\n' "$refs" | grep -q 'sigstore.bundle'
printf '%s\n' "$refs" | grep -q 'application/vnd.cyclonedx+json'
printf '%s\n' "$refs" | grep -q 'cv-oci.cve-verdict'
