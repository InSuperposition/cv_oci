#!/usr/bin/env bash
# setup-second-namespace.sh — stand up the second, independent build namespace.
# Chainsaw allocates exactly one ephemeral namespace per test; this suite needs
# two so the two builds share nothing (no cache, no repo, no RBAC).
#
#   SECOND_NS   the namespace to create (the suite passes <chainsaw-ns>-b)
#
# Creates it PSA-`restricted` (same as the Chainsaw one), seeds the pipeline
# RBAC, copies the zot CA, and applies the Task + Pipeline. Prints
# {"namespace":..}.
set -euo pipefail

: "${SECOND_NS:?set SECOND_NS}"
_here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/_resources/lib.sh
. "$_here/../_resources/lib.sh"
cd "$(cv_repo_root)"

kubectl create namespace "$SECOND_NS" >/dev/null
kubectl label namespace "$SECOND_NS" \
	pod-security.kubernetes.io/enforce=restricted \
	pod-security.kubernetes.io/enforce-version=latest >/dev/null

NS="$SECOND_NS" "$_here/../_resources/seed-pipeline-rbac.sh" >/dev/null
NS="$SECOND_NS" "$_here/../_resources/copy-zot-ca-to-namespace.sh" >/dev/null

kubectl apply -n "$SECOND_NS" -f tasks/buildpacks.yaml -f pipeline/pipeline.yaml >/dev/null

jq -nc --arg ns "$SECOND_NS" '{namespace: $ns}'
