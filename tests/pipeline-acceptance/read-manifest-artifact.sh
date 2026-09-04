#!/usr/bin/env bash
# read-manifest-artifact.sh — the deploy task's published manifest-artifact
# pair (P11b) plus where its CalVer tag actually points in zot.
#
#   NS   namespace of the PipelineRun `run`
#
#   {"url":..,"digest":"sha256:..","version":"0.X.Y","tag_digest":"sha256:..",
#    "expected_url":"<zot>/<ns>-frontend"}
#
# The chainsaw assert: tree checks: url == expected_url; digest is a sha256;
# version is CalVer-shaped; the CalVer tag resolves to that exact digest.
set -euo pipefail

: "${NS:?set NS}"
_here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/_resources/lib.sh
. "$_here/../_resources/lib.sh"
cd "$(cv_repo_root)"
zot=$(cv_zot)

pr() {
	kubectl -n "$NS" get pipelinerun run \
		-o jsonpath="{.status.results[?(@.name=='$1')].value}"
}

url=$(pr manifest-artifact-url)
digest=$(pr manifest-artifact-digest)
version=$(pr manifest-artifact-version)
tag_digest=$(crane digest --insecure "${url}:${version}" 2>/dev/null || true)

jq -nc \
	--arg url "$url" --arg digest "$digest" --arg version "$version" \
	--arg tag_digest "$tag_digest" --arg expected_url "${zot}/${NS}-frontend" \
	'{url:$url, digest:$digest, version:$version, tag_digest:$tag_digest, expected_url:$expected_url}'
