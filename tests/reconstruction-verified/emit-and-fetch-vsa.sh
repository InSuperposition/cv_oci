#!/usr/bin/env bash
# Emits a signed SLSA Verification Summary Attestation as an OCI referrer on the
# deployed cv digest — self-issued with the Tekton Chains key (single-actor
# cluster; see docs/debt.md) — then fetches it back and the surrounding referrer
# state. cosign 3.x needs BOTH --tlog-upload=false and --use-signing-config=false
# to stay off the public Rekor log, and a k8s:// key ref honours neither, so the
# Chains key is pulled to a file. Appended, not --replace'd.
#
#   {"vsa": <in-toto statement>, "expect_digest": <hex>,
#    "sbom_referrers": <int>, "verdict_referrers": <int>}
set -euo pipefail
_here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/reconstruction-verified/lib.sh
. "$_here/lib.sh"
cd "$(cv_repo_root)"

ref=$(cv_deployed_ref)
digest=${ref##*@}
vsa_type="https://slsa.dev/verification_summary/v1"

pred=$(mktemp)
jq --arg u "oci://${ref}" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '.resourceUri = $u | .timeVerified = $t' \
  tests/reconstruction-verified/vsa-predicate.json >"$pred"

kd=$(mktemp -d)
kubectl -n tekton-chains get secret signing-secrets \
  -o jsonpath='{.data.cosign\.key}' | base64 -d >"$kd/cosign.key"
COSIGN_PASSWORD="$(kubectl -n tekton-chains get secret signing-secrets \
  -o jsonpath='{.data.cosign\.password}' | base64 -d)"
export COSIGN_PASSWORD

cosign attest --key "$kd/cosign.key" --type "$vsa_type" --predicate "$pred" \
  --allow-insecure-registry --tlog-upload=false --use-signing-config=false "$ref" >/dev/null

pub=$(mktemp)
cv_chains_pubkey "$pub"
vsa=$(cosign verify-attestation --key "$pub" --insecure-ignore-tlog=true \
  --allow-insecure-registry --type "$vsa_type" "$ref" 2>/dev/null \
  | head -1 | jq -r '.payload' | base64 -d)

# a Chains SLSA provenance still verifies after the attest (coexistence)
cosign verify-attestation --key "$pub" --insecure-ignore-tlog=true \
  --allow-insecure-registry --type slsaprovenance1 "$ref" >/dev/null

refs=$(oras discover --insecure --format json "$ref")
jq -nc --argjson vsa "$vsa" --argjson refs "$refs" --arg d "${digest#sha256:}" '{
  vsa: $vsa,
  expect_digest: $d,
  sbom_referrers:    ([$refs.manifests[] | select(.artifactType == "application/vnd.cyclonedx+json")] | length),
  verdict_referrers: ([$refs.manifests[] | select(.artifactType == "application/vnd.cv-oci.cve-verdict.v1+json")] | length)
}'
