#!/usr/bin/env bash
# verify-manifest-artifact.sh — the deploy task published the Chains-signable
# manifest-artifact pair (P11b): bare URL + sha256 digest + CalVer version. This
# checks the artifact is really in zot at the CalVer tag, that Chains signed it
# async (a sigstore-bundle referrer lands within a few minutes), and that the
# signature verifies against the Chains key.
#
#   NS   namespace of the PipelineRun `run`
#
# T5a: asserts in-script. T5b splits into read-manifest-artifact.sh +
# ../_resources/fetch-artifact-referrers.sh + ../_resources/verify-image-signature.sh
# with assert: trees.
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
adigest=$(pr manifest-artifact-digest)
version=$(pr manifest-artifact-version)

[ "$url" = "${zot}/${NS}-frontend" ] || { echo "artifact url: $url" >&2; exit 1; }
printf '%s' "$adigest" | grep -Eqx 'sha256:[0-9a-f]{64}'
printf '%s' "$version" | grep -Eqx '0\.[0-9]+\.[0-9]+'

crane digest --insecure "${url}:${version}" >/dev/null
[ "$(crane digest --insecure "${url}:${version}")" = "$adigest" ] \
	|| { echo "tag $version does not point at $adigest" >&2; exit 1; }

ref="${url}@${adigest}"
for i in $(seq 1 30); do
	oras discover --insecure --format tree "$ref" 2>/dev/null \
		| grep -q 'sigstore.bundle' && break
	[ "$i" = 30 ] && { echo "no signature referrer on $ref" >&2; oras discover --insecure --format tree "$ref" >&2; exit 1; }
	sleep 10
done

pub=$(mktemp)
trap 'rm -f "$pub"' EXIT
cv_chains_pubkey "$pub"
cosign verify --key "$pub" --insecure-ignore-tlog=true --allow-insecure-registry "$ref" >/dev/null
