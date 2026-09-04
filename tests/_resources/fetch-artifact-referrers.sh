#!/usr/bin/env bash
# fetch-artifact-referrers.sh <ref> — list the artifactTypes of every OCI
# referrer on <ref>, polling until a Tekton Chains signature (sigstore bundle)
# referrer appears or the deadline passes.
#
# The wait loop lives HERE, not in a chainsaw `assert:` retry: a `command:`
# output binding is captured once, and a following `assert:` re-checks that
# static value — it does not re-run this fetch. Chains signs asynchronously, so
# the poll must be inside the script.
#
#   DEADLINE_SECONDS   how long to wait for the signature (default: 300)
#   POLL_INTERVAL_SECONDS  time between polls (default: 10; a bats case sets 0)
#
# Prints {"referrer_types":[..],"signed":bool}. Never fails on "not signed yet"
# past the deadline — it reports signed:false and the assert tree decides.
set -euo pipefail

# chainsaw templates `env` values, not `args` — call sites pass REF as env.
ref=${REF:-${1:?set REF (or pass <ref> as $1)}}
deadline=$(( $(date +%s) + ${DEADLINE_SECONDS:-300} ))
poll_interval=${POLL_INTERVAL_SECONDS:-10}

types='[]'
signed=false
while :; do
	types=$(oras discover --insecure --format json "$ref" 2>/dev/null \
		| jq -c '[.manifests[].artifactType] | unique' || echo '[]')
	if printf '%s' "$types" | jq -e 'any(. != null and startswith("application/vnd.dev.sigstore.bundle"))' >/dev/null 2>&1; then
		signed=true
		break
	fi
	[ "$(date +%s)" -ge "$deadline" ] && break
	sleep "$poll_interval"
done

jq -nc --argjson types "$types" --argjson signed "$signed" \
	'{referrer_types: $types, signed: $signed}'
