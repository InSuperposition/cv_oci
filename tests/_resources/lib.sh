#!/usr/bin/env bash
# Shared helpers for the cv_oci Chainsaw acceptance suites.
#
# Sourced, not executed. Every suite's scripts get these by
#   _here=$(cd "$(dirname "$0")" && pwd); . "$_here/../_resources/lib.sh"
# (or, for scripts that live in _resources/ themselves, "$_here/lib.sh").
#
# A helper here either prints a value or performs one small action — no
# comparisons. Comparisons live in the chainsaw-test.yaml `assert:` trees.
# shellcheck shell=bash

# Repo root — scripts cd here so paths and `. ./digests.env` resolve.
cv_repo_root() { git rev-parse --show-toplevel; }

# The one zot address, in-cluster and (on OrbStack) from the host. Override
# with CV_ZOT_ADDR in a test.
cv_zot() { printf '%s' "${CV_ZOT_ADDR:-zot.cv-pipeline.svc.cluster.local:5000}"; }

# Write the Tekton Chains cosign public key to the path in $1.
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
