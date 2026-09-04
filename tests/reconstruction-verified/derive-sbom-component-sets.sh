#!/usr/bin/env bash
# Emits the normalised CycloneDX component set — {name, version, purl}, sorted —
# from a fresh `trivy image` scan of the deployed cv digest, alongside the same
# projection of every deployed CycloneDX SBOM referrer. The raw SBOM bytes carry
# a per-run serialNumber + bom-ref UUIDs; only the set is stable (probe P17).
#
#   {"fresh": [ {name,version,purl}, … ], "deployed": [ [ … ], … ]}
set -euo pipefail
_here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/reconstruction-verified/lib.sh
. "$_here/lib.sh"
cd "$(cv_repo_root)"

ref=$(cv_deployed_ref)

fresh=$(mktemp)
trivy image --quiet --cache-dir "$CV_RECON_TRIVY_CACHE" --skip-db-update \
  --format cyclonedx --insecure "$ref" >"$fresh"

blobs=$(mktemp)
cv_referrer_blobs "$ref" application/vnd.cyclonedx+json >"$blobs"

jq -sc --slurpfile f "$fresh" \
  '{fresh: ([$f[0].components[] | {name, version, purl}] | sort_by(.purl, .name, .version)),
    deployed: [.[] | [.components[] | {name, version, purl}] | sort_by(.purl, .name, .version)]}' "$blobs"
