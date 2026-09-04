#!/usr/bin/env bash
# Renders modules/web-app/ at the deployed image digest + pinned cv_frontend
# fixture SHA, and fetches the cv-frontend manifest artifact the Flux
# OCIRepository actually reconciled (status.artifact.revision). Emits both as
# text for a byte comparison.
#
#   {"fresh": "<rendered yaml>", "deployed": "<reconciled yaml>"}
set -euo pipefail
_here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/reconstruction-verified/lib.sh
. "$_here/lib.sh"
cd "$(cv_repo_root)"
# shellcheck source=/dev/null
. ./digests.env

zot=$(cv_zot)
digest=$(cv_deployed_digest)

vals="$(mktemp -d)/values.cue"   # timoni keys the parser off the extension
cat >"$vals" <<EOF
values: {
	image:       "${zot}/cv@${digest}"
	appVersion:  "${FRONTEND_FIXTURE_SHA}"
	extraLabels: {"app.kubernetes.io/part-of": "cv-oci"}
}
EOF

fresh=$(mktemp)
timoni build cv ./modules/web-app -n cv-pipeline -f "$vals" >"$fresh"

rev=$(kubectl -n flux-system get ocirepository cv-frontend \
  -o jsonpath='{.status.artifact.revision}')
lyr=$(oras manifest fetch --insecure "${zot}/cv-frontend:${rev%@*}" | jq -r '.layers[0].digest')
deployed=$(mktemp)
oras blob fetch --insecure --output - "${zot}/cv-frontend@${lyr}" | tar -xzO >"$deployed"

jq -nc --rawfile a "$fresh" --rawfile b "$deployed" '{fresh: $a, deployed: $b}'
