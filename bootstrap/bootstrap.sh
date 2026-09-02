#!/usr/bin/env bash
# bootstrap.sh — bring an OrbStack cluster from zero to "ready for cv_oci".
#
# Ordered, --wait-gated, idempotent. Re-running on a ready cluster is a no-op.
#
#   phase 1  Tekton Pipelines v1.15.1 (vendored, checksum-pinned)
#   phase 1b cert-manager (vendored, checksum-pinned) + the cv-oci CA issuers
#   phase 2  feature flags: git resolver + set-security-context (Slice 1.7 PSA)
#   phase 3  cv-pipeline namespace + RBAC + ServiceAccount
#   phase 4  zot seed (TLS via cert-manager) + the cv-build pipeline
#   phase 5  Tekton Chains (vendored) — x509 signing, sigstore-bundle referrers
#
# Per-platform node trust for the CNB pull path (docs/runbook.md) is NOT done
# here — it changes host config. phase 4 prints the two commands.
#
# Flags: --skip-pipeline   stop after phase 3
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/log.sh
source "$ROOT/scripts/lib/log.sh"
cd "$ROOT"

need kubectl

TEKTON_VERSION="v1.15.1"
TEKTON_YAML="vendor/tekton/pipeline-${TEKTON_VERSION}.yaml"
TEKTON_SHA256="68da92cc20086184b795dae6ce425c47fe6ca3ee82b288b228bcce76bb4b3c86"

CERT_MANAGER_VERSION="v1.21.1"
CERT_MANAGER_YAML="vendor/cert-manager/cert-manager-${CERT_MANAGER_VERSION}.yaml"
CERT_MANAGER_SHA256="5f6a499b8c1857d57f560f536e0dcc830914b45c420899fe7ad0692c8624e408"

CHAINS_VERSION="v0.29.0"
CHAINS_YAML="vendor/tekton-chains/chains-${CHAINS_VERSION}.yaml"
CHAINS_SHA256="97d68bb6d8d7d60705a88ec77746c5dd3cc361e29caae4f3789ba87cd2aaaef2"

phase() { printf '\n=== phase %s: %s ===\n' "$1" "$2" >&2; }

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

# ---- phase 1b ------------------------------------------------------------
phase 1b "cert-manager ${CERT_MANAGER_VERSION}"
echo "${CERT_MANAGER_SHA256}  ${CERT_MANAGER_YAML}" | shasum -a 256 -c - >/dev/null \
	|| die "cert-manager release checksum mismatch: ${CERT_MANAGER_YAML}"

if kubectl get deploy/cert-manager -n cert-manager \
	-o jsonpath='{.metadata.labels.app\.kubernetes\.io/version}' 2>/dev/null \
	| grep -qx "${CERT_MANAGER_VERSION}"; then
	log_kv step=cert-manager state=already-installed version="${CERT_MANAGER_VERSION}"
else
	kubectl apply -f "${CERT_MANAGER_YAML}" >/dev/null
	log_kv step=cert-manager action=applied
fi

log_kv step=cert-manager waiting=available
kubectl wait --for=condition=Available --timeout=180s -n cert-manager \
	deploy/cert-manager deploy/cert-manager-webhook deploy/cert-manager-cainjector >/dev/null
# The webhook needs its own serving cert wired before it will admit our CRs.
kubectl wait --for=condition=Established --timeout=60s \
	crd/certificates.cert-manager.io crd/clusterissuers.cert-manager.io >/dev/null

log_kv step=cert-manager action=apply-issuers
# Retry: the webhook can 500 for a few seconds after Available while its cert
# propagates.
for i in 1 2 3 4 5 6; do
	kubectl apply -f manifests/cert-manager/issuers.yaml >/dev/null 2>&1 && break
	[ "$i" -eq 6 ] && kubectl apply -f manifests/cert-manager/issuers.yaml >/dev/null
	sleep 5
done
kubectl wait --for=condition=Ready --timeout=120s -n cert-manager certificate/cv-oci-ca >/dev/null
log_kv step=cert-manager state=ca-ready

# ---- phase 2 -------------------------------------------------------------
phase 2 "feature flags"
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

# Slice 1.7: cv-pipeline enforces PodSecurity `restricted`. Tekton injects init
# containers (prepare, working-dir-initializer, place-scripts) and the results
# sidecar; set-security-context=true makes the controller stamp a
# restricted-compliant securityContext on them. Without it every PipelineRun in
# cv-pipeline is rejected at admission. Needs a controller restart to take.
secctx="$(kubectl get configmap feature-flags -n tekton-pipelines \
	-o jsonpath='{.data.set-security-context}' 2>/dev/null || echo '')"
if [ "$secctx" = "true" ]; then
	log_kv step=set-security-context state=enabled
else
	kubectl patch configmap feature-flags -n tekton-pipelines \
		--type merge -p '{"data":{"set-security-context":"true"}}' >/dev/null
	kubectl rollout restart deploy/tekton-pipelines-controller -n tekton-pipelines >/dev/null
	kubectl rollout status deploy/tekton-pipelines-controller -n tekton-pipelines --timeout=180s >/dev/null
	log_kv step=set-security-context action=enabled
fi

# ---- phase 3 -----------------------------------------------------------
phase 3 "cv-pipeline namespace + RBAC"
kubectl apply -f manifests/namespace.yaml -f manifests/rbac.yaml >/dev/null
kubectl -n cv-pipeline get serviceaccount cv-build-sa cv-smoke-sa cv-deploy-sa >/dev/null
log_kv step=namespace state=ready ns=cv-pipeline sa="cv-build-sa,cv-smoke-sa,cv-deploy-sa"

if [ "${1:-}" = "--skip-pipeline" ]; then
	log_kv step=bootstrap result=ok note="stopped after phase 3 (--skip-pipeline)"
	exit 0
fi

# ---- phase 4 --------------------------------------------------------
phase 4 "zot seed + cv-build pipeline"
# shellcheck disable=SC1091
source digests.env
[ -n "${ZOT:-}" ] || die "phase 4: images.zot not pinned in digests.cue"

kubectl apply -f manifests/zot/configmap.yaml -f manifests/zot/pvc.yaml \
	-f manifests/zot/service.yaml -f manifests/zot/certificate.yaml >/dev/null
kubectl wait --for=condition=Ready --timeout=120s -n cv-pipeline certificate/zot-tls >/dev/null
log_kv step=zot state=tls-cert-ready
sed "s|\${ZOT}|${ZOT}|g" manifests/zot/deployment.yaml | kubectl apply -f - >/dev/null
log_kv step=zot waiting=available
kubectl -n cv-pipeline rollout status deploy/zot --timeout=120s >/dev/null

kubectl -n cv-pipeline apply -f tasks/buildpacks.yaml -f pipeline/pipeline.yaml >/dev/null
log_kv step=pipeline state=applied

# ---- phase 5 --------------------------------------------------------
phase 5 "Tekton Chains ${CHAINS_VERSION}"
need cosign
echo "${CHAINS_SHA256}  ${CHAINS_YAML}" | shasum -a 256 -c - >/dev/null \
	|| die "Chains release checksum mismatch: ${CHAINS_YAML}"

if kubectl get deploy/tekton-chains-controller -n tekton-chains \
	-o jsonpath='{.metadata.labels.app\.kubernetes\.io/version}' 2>/dev/null \
	| grep -qx "${CHAINS_VERSION}"; then
	log_kv step=chains state=already-installed version="${CHAINS_VERSION}"
else
	kubectl apply -f "${CHAINS_YAML}" >/dev/null
	log_kv step=chains action=applied
fi
kubectl wait --for=condition=Available --timeout=180s -n tekton-chains \
	deploy/tekton-chains-controller >/dev/null

# Config + the CA trust the controller needs to push to the TLS zot.
kubectl apply -f manifests/chains/config.yaml -f manifests/chains/ca-cert.yaml >/dev/null
kubectl wait --for=condition=Ready --timeout=120s -n tekton-chains certificate/cv-oci-ca >/dev/null
kubectl -n tekton-chains patch deploy tekton-chains-controller \
	--patch-file manifests/chains/controller-ca-patch.yaml >/dev/null

# Signing key — generate ONLY if absent (bisect safety: a re-bootstrap on an
# older checkout must not mint a new key that fails verify against prior sigs).
if kubectl -n tekton-chains get secret signing-secrets \
	-o jsonpath='{.data.cosign\.key}' 2>/dev/null | grep -q .; then
	log_kv step=chains state=signing-key-present
else
	COSIGN_PASSWORD="" cosign generate-key-pair k8s://tekton-chains/signing-secrets >/dev/null
	rm -f cosign.pub
	log_kv step=chains action=signing-key-generated
fi

kubectl -n tekton-chains rollout restart deploy/tekton-chains-controller >/dev/null
kubectl -n tekton-chains rollout status deploy/tekton-chains-controller --timeout=180s >/dev/null
log_kv step=chains state=ready

cat >&2 <<'NOTE'

  The CNB pull path needs two one-time OrbStack node steps (docs/runbook.md).
  zot now speaks TLS with a cert-manager self-signed CA; the insecure-registries
  entry stays — it means "accept an unverified cert for this host", which is
  what a self-signed cert is, so no CA import on the node.
    orb config set k8s.expose_services true      # then: orb stop / restart
    #  ~/.orbstack/config/docker.json:
    #  {"insecure-registries":["zot.cv-pipeline.svc.cluster.local:5000"]}
    orb restart docker

NOTE

log_kv step=bootstrap result=ok
