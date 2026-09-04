#!/usr/bin/env bash
# reconstruction-verified — suite-local helpers.
#
# Shared helpers (cv_repo_root, cv_zot, cv_chains_pubkey, cv_referrer_blobs)
# now live in tests/_resources/lib.sh; this file sources them and adds only what
# is specific to verifying the LIVE deployed cv image.
#
# Sourced, not executed. Scripts here still do data-gathering only and print one
# JSON object; comparisons live in chainsaw-test.yaml `assert:` trees.
# shellcheck shell=bash

# shellcheck source=tests/_resources/lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../_resources/lib.sh"

# Run-fixed Trivy cache: prime-pinned-trivy-db.sh fills it once with the
# digest-pinned DB; the SBOM + CVE derivations read it with --skip-db-update so
# the verdict depends only on (image digest, DB digest). Override for tests.
: "${CV_RECON_TRIVY_CACHE:=/tmp/cv-recon-trivydb}"
export CV_RECON_TRIVY_CACHE

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
