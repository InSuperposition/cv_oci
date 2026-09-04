#!/usr/bin/env bash
# Attempts `cosign verify-attestation` of the VSA on the deployed cv digest with
# a throwaway keypair and emits the exit code. Non-zero == the foreign key is
# correctly rejected.
#
#   {"verify_rc": <int>}
set -euo pipefail
_here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/reconstruction-verified/lib.sh
. "$_here/lib.sh"

ref=$(cv_deployed_ref)

fk=$(mktemp -d)
(cd "$fk" && COSIGN_PASSWORD="" cosign generate-key-pair >/dev/null)

rc=0
cosign verify-attestation --key "$fk/cosign.pub" --insecure-ignore-tlog=true \
  --allow-insecure-registry --type "https://slsa.dev/verification_summary/v1" \
  "$ref" >/dev/null 2>&1 || rc=$?

jq -nc --argjson rc "$rc" '{verify_rc: $rc}'
