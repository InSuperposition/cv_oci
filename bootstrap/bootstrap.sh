#!/usr/bin/env bash
# bootstrap.sh — bring an OrbStack cluster from zero to "ready for cv_oci Slice 1".
#
# Ordered, --wait-gated, idempotent. Re-running on a ready cluster is a no-op.
#
#   phase 0  host toolchain check (informational)
#   phase 1  Tekton Pipelines v1.15.1 (vendored, checksum-pinned)
#   phase 2  verify the git resolver is enabled (on by default in v1.15.1)
#   phase 3  cv-pipeline namespace + RBAC + ServiceAccount
#   phase 4  build + docker-load the pipeline-utils image
#
# No registry, CA, or NetworkPolicy in Slice 1 (design doc / docs/debt.md).
#
# Flags: --skip-pipeline-utils   stop after phase 3
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/log.sh
source "$ROOT/scripts/lib/log.sh"
cd "$ROOT"

need kubectl

TEKTON_VERSION="v1.15.1"
TEKTON_YAML="vendor/tekton/pipeline-${TEKTON_VERSION}.yaml"
TEKTON_SHA256="68da92cc20086184b795dae6ce425c47fe6ca3ee82b288b228bcce76bb4b3c86"

phase() { printf '\n=== phase %s: %s ===\n' "$1" "$2" >&2; }

# ---- phase 0 -----------------------------------------------------------------
phase 0 "host toolchain"
scripts/check-toolchain.sh || true

# ---- phase 1 ---------------------------------------------------------------
phase 1 "Tekton Pipelines ${TEKTON_VERSION}"
echo "${TEKTON_SHA256}  ${TEKTON_YAML}" | shasum -a 256 -c - >/dev/null \
	|| die "Tekton release checksum mismatch: ${TEKTON_YAML}"

if kubectl get deploy/tekton-pipelines-controller -n tekton-pipelines \
	-o jsonpath='{.metadata.labels.pipeline\.tekton\.dev/release}' 2>/dev/null \
	| grep -qx "${TEKTON_VERSION}"; then
	log_kv step=tekton state=already-installed version="${TEKTON_VERSION}"
else
	kubectl apply -f "${TEKTON_YAML}" >/dev/null
	log_kv step=tekton action=applied
fi

log_kv step=tekton waiting=crds-established
kubectl wait --for=condition=Established --timeout=120s \
	crd/tasks.tekton.dev crd/pipelines.tekton.dev \
	crd/taskruns.tekton.dev crd/pipelineruns.tekton.dev \
	crd/resolutionrequests.resolution.tekton.dev >/dev/null

log_kv step=tekton waiting=controllers-available
kubectl wait --for=condition=Available --timeout=180s -n tekton-pipelines \
	deploy/tekton-pipelines-controller deploy/tekton-pipelines-webhook >/dev/null
kubectl wait --for=condition=Available --timeout=180s -n tekton-pipelines-resolvers \
	deploy/tekton-pipelines-remote-resolvers >/dev/null

# ---- phase 2 -------------------------------------------------------------
phase 2 "git resolver"
enabled="$(kubectl get configmap resolvers-feature-flags -n tekton-pipelines-resolvers \
	-o jsonpath='{.data.enable-git-resolver}' 2>/dev/null || echo '')"
if [ "$enabled" = "true" ]; then
	log_kv step=git-resolver state=enabled
else
	kubectl patch configmap resolvers-feature-flags -n tekton-pipelines-resolvers \
		--type merge -p '{"data":{"enable-git-resolver":"true"}}' >/dev/null
	kubectl rollout restart deploy/tekton-pipelines-remote-resolvers -n tekton-pipelines-resolvers >/dev/null
	kubectl rollout status deploy/tekton-pipelines-remote-resolvers -n tekton-pipelines-resolvers --timeout=120s >/dev/null
	log_kv step=git-resolver action=enabled
fi

# ---- phase 3 -----------------------------------------------------------
phase 3 "cv-pipeline namespace + RBAC"
kubectl apply -f manifests/namespace.yaml -f manifests/rbac.yaml >/dev/null
kubectl -n cv-pipeline get serviceaccount cv-pipeline-sa >/dev/null
log_kv step=namespace state=ready ns=cv-pipeline sa=cv-pipeline-sa

# ---- phase 4 --------------------------------------------------------
if [ "${1:-}" = "--skip-pipeline-utils" ]; then
	log_kv step=bootstrap result=ok note="stopped before phase 4 (--skip-pipeline-utils)"
	exit 0
fi
phase 4 "pipeline-utils image"
bootstrap/build-pipeline-utils.sh

log_kv step=bootstrap result=ok
