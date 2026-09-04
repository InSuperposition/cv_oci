#!/usr/bin/env bash
# seed-pipeline-rbac.sh — imperatively create the per-stage pipeline RBAC (3
# ServiceAccounts + 1 RoleBinding to the shared ClusterRole) in $NS.
#
# The single-namespace suites use a ($namespace)-templated `apply:` of
# ../_resources/pipeline-rbac.yaml. This script is for a namespace Chainsaw does
# NOT manage (build-is-reproducible's second namespace) — Chainsaw can only
# template the apply to the test's own ephemeral namespace, so a second one is
# seeded here with `kubectl create`, no stream editor, no rbac duplication.
#
# cv-build-sa and cv-deploy-sa get no RoleBinding — neither task touches the
# K8s API (cv-deploy-sa retired 2026-09-04, see manifests/rbac.yaml).
#
#   NS   target namespace
#
# Prints {"namespace":..,"serviceaccounts":3,"rolebindings":1}.
set -euo pipefail

: "${NS:?set NS}"

kubectl -n "$NS" create serviceaccount cv-build-sa >/dev/null
kubectl -n "$NS" patch serviceaccount cv-build-sa \
	-p '{"automountServiceAccountToken":false}' >/dev/null
kubectl -n "$NS" create serviceaccount cv-smoke-sa >/dev/null
kubectl -n "$NS" create serviceaccount cv-deploy-sa >/dev/null
kubectl -n "$NS" patch serviceaccount cv-deploy-sa \
	-p '{"automountServiceAccountToken":false}' >/dev/null
kubectl -n "$NS" create rolebinding cv-smoke-rolebinding \
	--clusterrole cv-smoke-role --serviceaccount "${NS}:cv-smoke-sa" >/dev/null

jq -nc --arg ns "$NS" '{namespace: $ns, serviceaccounts: 3, rolebindings: 1}'
