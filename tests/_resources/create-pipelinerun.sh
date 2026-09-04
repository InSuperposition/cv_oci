#!/usr/bin/env bash
# create-pipelinerun.sh — render (and, unless DRY_RUN, create) one cv-build
# PipelineRun. Replaces the ~40-line manifest heredoc the five pipeline-running
# suites each hand-rolled.
#
# All image refs come from digests.env (the pinned digests). Per-suite variance
# is env:
#
#   NS                     (required) target namespace + the `namespace` param
#   ACCEPTANCE_LABEL        (required) value of the cv-oci/acceptance-test label
#   RUN_NAME               metadata.name (default: run) — deterministic, NOT
#                          generateName, so every later chainsaw step selects it
#                          by exact name (chainsaw 0.2.15 drops cross-step
#                          `outputs` bindings) and there is never a stale
#                          `.items[0]` to match.
#   FRONTEND_REF           frontend-ref param (default: FRONTEND_FIXTURE_SHA)
#   APP_REPO              app-repo param       (default: <zot>/<NS>)
#   DEPLOY_ARTIFACT_REPO   deploy-artifact-repo (default: <APP_REPO>-frontend)
#   PIPELINE_REF           pipeline-ref param   (default: git rev-parse HEAD —
#                          the `fetch` step clones cv_oci@this remotely for
#                          modules/, so the commit MUST be pushed)
#   PIPELINE_TIMEOUT       spec.timeouts.pipeline (default: 25m)
#   DRY_RUN               non-empty -> print the manifest to stdout and exit;
#                          do not call kubectl (used by the bats case, piped to
#                          kubeconform)
#
# Non-dry-run: creates the PipelineRun and prints {"name":..,"namespace":..}.
set -euo pipefail

_here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/_resources/lib.sh
. "$_here/lib.sh"

cd "$(cv_repo_root)"
# shellcheck source=/dev/null
. ./digests.env

: "${NS:?set NS}"
: "${ACCEPTANCE_LABEL:?set ACCEPTANCE_LABEL}"
run_name=${RUN_NAME:-run}
frontend_ref=${FRONTEND_REF:-$FRONTEND_FIXTURE_SHA}
zot=$(cv_zot)
app_repo=${APP_REPO:-${zot}/${NS}}
deploy_artifact_repo=${DEPLOY_ARTIFACT_REPO:-${app_repo}-frontend}
pipeline_ref=${PIPELINE_REF:-$(git rev-parse HEAD)}
pipeline_timeout=${PIPELINE_TIMEOUT:-25m}

manifest=$(cat <<EOF
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  name: ${run_name}
  namespace: ${NS}
  labels:
    cv-oci/acceptance-test: ${ACCEPTANCE_LABEL}
spec:
  pipelineRef:
    name: cv-build
  taskRunTemplate:
    serviceAccountName: cv-build-sa
    podTemplate:
      securityContext:
        fsGroup: 1000
      nodeSelector:
        kubernetes.io/arch: arm64
  taskRunSpecs:
    - pipelineTaskName: smoke
      serviceAccountName: cv-smoke-sa
    - pipelineTaskName: smoke-teardown
      serviceAccountName: cv-smoke-sa
    - pipelineTaskName: deploy
      serviceAccountName: cv-deploy-sa
  params:
    - name: builder-image
      value: "docker.io/heroku/builder:24@${CNBBUILDER}"
    - name: run-image
      value: "docker.io/heroku/heroku:24@${CNBRUNIMAGE}"
    - name: utility-image
      value: "docker.io/library/bash@${CNBUTILITYIMAGE}"
    - name: kubectl-image
      value: "docker.io/alpine/k8s:1.31.1@${CNBKUBECTLIMAGE}"
    - name: git-image
      value: "docker.io/alpine/git@${CNBGITIMAGE}"
    - name: trivy-image
      value: "ghcr.io/aquasecurity/trivy@${TRIVYCLI}"
    - name: oras-image
      value: "ghcr.io/oras-project/oras@${ORASCLI}"
    - name: trivy-db
      value: "${TRIVYDB}"
    - name: frontend-repo
      value: "${FRONTEND_REPO}"
    - name: frontend-ref
      value: "${frontend_ref}"
    - name: app-repo
      value: "${app_repo}"
    - name: deploy-artifact-repo
      value: "${deploy_artifact_repo}"
    - name: namespace
      value: "${NS}"
    - name: pipeline-ref
      value: "${pipeline_ref}"
    - name: render-image
      value: "${zot}/timoni@${TIMONIIMAGE}"
    - name: flux-cli-image
      value: "ghcr.io/fluxcd/flux-cli@${FLUXCLI}"
  workspaces:
    - name: shared
      volumeClaimTemplate:
        spec:
          accessModes: [ReadWriteOnce]
          resources:
            requests:
              storage: 3Gi
  timeouts:
    pipeline: ${pipeline_timeout}
EOF
)

if [ -n "${DRY_RUN:-}" ]; then
	printf '%s\n' "$manifest"
	exit 0
fi

printf '%s\n' "$manifest" | kubectl -n "$NS" create -f - >/dev/null
jq -nc --arg n "$run_name" --arg ns "$NS" '{name: $n, namespace: $ns}'
