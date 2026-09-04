#!/usr/bin/env bash
# derive-layer-hashes.sh — print the CNB lifecycle's own content-addressed
# layer hashes for both independent builds as JSON:
#   - app-layer diffID   io.buildpacks.lifecycle.metadata .app[0].sha
#   - SBOM-layer diffID  io.buildpacks.lifecycle.metadata .sbom.sha
# plus the two outer image digests (bonus, non-load-bearing).
#
#   NS1   the Chainsaw ephemeral namespace (the second is <NS1>-b)
#
#   {"app1":..,"app2":..,"sbom1":..,"sbom2":..,"ref1":..,"ref2":..}
#
# The chainsaw assert: tree checks app1==app2 and sbom1==sbom2.
set -euo pipefail

: "${NS1:?set NS1}"
_here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/_resources/lib.sh
. "$_here/../_resources/lib.sh"
cd "$(cv_repo_root)"
zot=$(cv_zot)
ns2="${NS1}-b"

lifecycle_sha() { # <image-ref> <jq path into the metadata label>
	crane config --insecure "$1" \
		| jq -r ".config.Labels[\"io.buildpacks.lifecycle.metadata\"] | fromjson | $2"
}

img_of() { # <namespace>
	local d
	d=$(kubectl -n "$1" get pipelinerun run \
		-o jsonpath='{.status.results[?(@.name=="app-image-digest")].value}')
	printf '%s' "${zot}/$1@${d}"
}

ref1=$(img_of "$NS1")
ref2=$(img_of "$ns2")

jq -nc \
	--arg ref1 "$ref1" --arg ref2 "$ref2" \
	--arg app1 "$(lifecycle_sha "$ref1" '.app[0].sha')" \
	--arg app2 "$(lifecycle_sha "$ref2" '.app[0].sha')" \
	--arg sbom1 "$(lifecycle_sha "$ref1" '.sbom.sha')" \
	--arg sbom2 "$(lifecycle_sha "$ref2" '.sbom.sha')" \
	'{ref1:$ref1, ref2:$ref2, app1:$app1, app2:$app2, sbom1:$sbom1, sbom2:$sbom2}'
