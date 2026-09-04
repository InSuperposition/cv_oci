#!/usr/bin/env bash
# Verifies the Tekton Chains SLSA-provenance signature on the deployed cv digest
# (a non-zero exit here fails the chainsaw step before any assert), then emits
# the decoded in-toto statement plus the pinned values it must agree with:
#
#   {"statement": <in-toto statement>,
#    "expect": {"digest": <hex>, "builder": <hex>, "runimg": <hex>, "fixture": <sha>}}
#
# All slsaprovenance1 attestations on the digest are byte-identical genuine
# provenance; one is emitted.
set -euo pipefail
_here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/reconstruction-verified/lib.sh
. "$_here/lib.sh"
cd "$(cv_repo_root)"
# shellcheck source=/dev/null
. ./digests.env

ref=$(cv_deployed_ref)
digest=${ref##*@}
pub=$(mktemp)
cv_chains_pubkey "$pub"

cosign verify-attestation --key "$pub" --insecure-ignore-tlog=true \
  --allow-insecure-registry --type slsaprovenance1 "$ref" >/dev/null

cosign verify-attestation --key "$pub" --insecure-ignore-tlog=true \
  --allow-insecure-registry --type slsaprovenance1 "$ref" 2>/dev/null \
  | head -1 | jq -r '.payload' | base64 -d \
  | jq -c --arg d "${digest#sha256:}" --arg b "${CNBBUILDER#sha256:}" \
          --arg r "${CNBRUNIMAGE#sha256:}" --arg fx "$FRONTEND_FIXTURE_SHA" \
      '{statement: ., expect: {digest: $d, builder: $b, runimg: $r, fixture: $fx}}'
