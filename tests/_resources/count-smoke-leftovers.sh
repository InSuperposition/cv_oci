#!/usr/bin/env bash
# count-smoke-leftovers.sh — print how many Deployments + Services are still
# labelled cv-oci/smoke in the namespace. The ephemeral smoke instance must be
# torn down even when smoke fails (the `finally` smoke-teardown), so the
# chainsaw assert: tree checks this is 0.
#
#   NS   the namespace the run lives in
#
#   {"leftovers": 0}
set -euo pipefail

: "${NS:?set NS}"

n=$(kubectl -n "$NS" get deploy,svc -l cv-oci/smoke -o name 2>/dev/null | grep -c . || true)

jq -nc --argjson n "${n:-0}" '{leftovers: $n}'
