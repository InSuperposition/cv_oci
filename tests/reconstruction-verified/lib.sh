#!/usr/bin/env bash
# Shared data-gathering helpers for the reconstruction-verified suite.
#
# These scripts ONLY fetch / derive and print one JSON object to stdout. Every
# comparison lives in chainsaw-test.yaml's `assert:` (kyverno-json) trees — no
# `jq -e`, `diff` or `[ … ]` doing the checking here. Sourced, not executed.
# shellcheck shell=bash

# Run-fixed Trivy cache: prime-pinned-trivy-db.sh fills it once with the
# digest-pinned DB; the SBOM + CVE derivations read it with --skip-db-update so
# the verdict depends only on (image digest, DB digest). Override for tests.
: "${CV_RECON_TRIVY_CACHE:=/tmp/cv-recon-trivydb}"
export CV_RECON_TRIVY_CACHE

cv_repo_root() { git rev-parse --show-toplevel; }

cv_zot() { printf '%s' "${CV_ZOT_ADDR:-zot.cv-pipeline.svc.cluster.local:5000}"; }

# The digest-pinned image ref the Flux Kustomization rolled out into cv-pipeline.
cv_deployed_ref() {
  local img zot
  img=$(kubectl -n cv-pipeline get deploy cv \
    -o jsonpath='{.spec.template.spec.containers[0].image}')
  zot=$(cv_zot)
  case "$img" in
    "$zot"/cv@sha256:*) printf '%s' "$img" ;;
    *) echo "cv Deployment absent or not digest-pinned in cv-pipeline — run the deploy-via-flux path first" >&2
       return 1 ;;
  esac
}

cv_deployed_digest() { local r; r=$(cv_deployed_ref) && printf '%s' "${r##*@}"; }

# Write the Tekton Chains public key to the path in $1.
cv_chains_pubkey() { cosign public-key --key k8s://tekton-chains/signing-secrets >"$1"; }

# Stream the layer-blob bytes of every referrer of artifactType $2 on ref $1 —
# one JSON document per referrer, concatenated on stdout. Callers slurp with
# `jq -s`.
cv_referrer_blobs() {
  local ref=$1 type=$2 repo=${1%@*} m bl
  oras discover --insecure --format json "$ref" \
    | jq -r --arg t "$type" '.manifests[] | select(.artifactType == $t) | .digest' \
    | while read -r m; do
        bl=$(oras manifest fetch --insecure "${repo}@${m}" | jq -r '.layers[0].digest')
        oras blob fetch --insecure --output - "${repo}@${bl}"
      done
}
