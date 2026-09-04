#!/usr/bin/env bash
# count-smoke-leftovers.sh — count the Deployments + Services still labelled
# cv-oci/smoke in the namespace. The ephemeral smoke instance must be torn down
# even when smoke fails (the `finally` smoke-teardown), so this must be 0.
#
#   NS   the namespace the run lives in
#
# T4a asserts here; T4b prints {"leftovers": N} and the assert: tree checks it.
set -euo pipefail

: "${NS:?set NS}"

n=$(kubectl -n "$NS" get deploy,svc -l cv-oci/smoke -o name 2>/dev/null | grep -c . || true)
[ "$n" = "0" ] || { echo "smoke leftovers: $n" >&2; exit 1; }
