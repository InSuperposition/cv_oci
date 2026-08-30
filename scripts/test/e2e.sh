#!/usr/bin/env bash
# e2e.sh — the executable Slice 1 acceptance test.
#
# Runs the real cv-slice1 Pipeline against the live OrbStack cluster with the
# pinned cv_frontend fixture SHA, in a unique throwaway namespace. Captures all
# run evidence BEFORE teardown, asserts the full success contract, and cleans
# up (namespace + the built image) even if an assertion fails.
#
#   scripts/test/e2e.sh            happy path
#   scripts/test/e2e.sh --keep     leave the namespace + artifacts for inspection
#
# Needs: kubectl, tkn, crane, docker, jq  (host tools). A working cluster with
# `bootstrap/bootstrap.sh` already run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=scripts/lib/log.sh
source "$ROOT/scripts/lib/log.sh"
cd "$ROOT"
need kubectl; need tkn; need crane; need docker; need jq

KEEP=0
[ "${1:-}" = "--keep" ] && KEEP=1

# shellcheck disable=SC1091
source digests.env
FIXTURE_SHA="$FRONTEND_FIXTURE_SHA"
FRONTEND_REPO_URL="$FRONTEND_REPO"
OCI_REPO_URL="${CV_OCI_REPO:-https://github.com/InSuperposition/cv_oci}"
OCI_REF="${CV_OCI_REF:-main}"
UTILS_IMAGE="cv/pipeline-utils:slice1-arm64"

# resolve the pinned digests cue -> the two base images
BUILD_IMAGE="docker.io/library/node:24-bookworm-slim@${NODEBUILD}"
DISTROLESS="gcr.io/distroless/nodejs24-debian12@${DISTROLESSNODE}"

UID_SUFFIX="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
NS="cv-e2e-${UID_SUFFIX}"
ART="$ROOT/scripts/test/_artifacts/${NS}"
mkdir -p "$ART"
IMAGE_TAG="cv:git-${FIXTURE_SHA}"

FAILURES=0
check() { # check <label> <condition-command...>
	local label="$1"; shift
	if "$@" >/dev/null 2>&1; then
		printf '  PASS  %s\n' "$label"
	else
		printf '  FAIL  %s\n' "$label"
		FAILURES=$((FAILURES + 1))
	fi
}

capture() {
	log_kv step=e2e action=capture-evidence dir="$ART"
	kubectl -n "$NS" get pipelinerun "$PRN" -o yaml   > "$ART/pipelinerun.yaml"   2>&1 || true
	kubectl -n "$NS" get taskruns -o yaml             > "$ART/taskruns.yaml"      2>&1 || true
	kubectl -n "$NS" get events --sort-by=.lastTimestamp > "$ART/events.txt"      2>&1 || true
	kubectl -n "$NS" get pods -o wide                 > "$ART/pods.txt"           2>&1 || true
	tkn -n "$NS" pipelinerun logs "$PRN"              > "$ART/pipeline.log"       2>&1 || true
	kubectl -n "$NS" get deploy,svc,cm -o yaml        > "$ART/deployed.yaml"      2>&1 || true
}

cleanup() {
	local rc=$?
	[ -n "${PRN:-}" ] && capture
	if [ "$KEEP" -eq 1 ]; then
		log_kv step=e2e action=kept ns="$NS" artifacts="$ART"
	else
		kubectl delete ns "$NS" --wait=false >/dev/null 2>&1 || true
		docker rmi "$IMAGE_TAG" >/dev/null 2>&1 || true
		rm -rf "$ART"
	fi
	exit $rc
}
trap cleanup EXIT

log_kv step=e2e action=setup ns="$NS" fixture="$FIXTURE_SHA"
kubectl create ns "$NS" >/dev/null
# everything for this run lives in $NS: RBAC + SA, the Tasks, the Pipeline, and
# the deployed app. Deleting the namespace deletes all of it.
sed "s/namespace: cv-pipeline/namespace: $NS/" manifests/rbac.yaml | kubectl apply -f - >/dev/null
kubectl -n "$NS" apply -f tasks/ -f pipeline/ >/dev/null

PRN="$(kubectl -n "$NS" create -o name -f - <<EOF | sed 's#.*/##'
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata: { generateName: e2e- }
spec:
  pipelineRef: { name: cv-slice1 }
  taskRunTemplate:
    serviceAccountName: cv-pipeline-sa
    podTemplate: { securityContext: { fsGroup: 65532 } }
  params:
    - { name: utils-image, value: "$UTILS_IMAGE" }
    - { name: build-image, value: "$BUILD_IMAGE" }
    - { name: distroless-base, value: "$DISTROLESS" }
    - { name: frontend-repo, value: "$FRONTEND_REPO_URL" }
    - { name: frontend-ref, value: "$FIXTURE_SHA" }
    - { name: oci-repo, value: "$OCI_REPO_URL" }
    - { name: oci-ref, value: "$OCI_REF" }
    - { name: namespace, value: "$NS" }
  workspaces:
    - name: shared
      volumeClaimTemplate:
        spec: { accessModes: [ReadWriteOnce], resources: { requests: { storage: 3Gi } } }
EOF
)"
log_kv step=e2e action=pipelinerun-started run="$PRN"

# wait for completion (10 min ceiling)
deadline=$(( $(date +%s) + 600 ))
while :; do
	status="$(kubectl -n "$NS" get pipelinerun "$PRN" -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || true)"
	if [ "$status" = "True" ]; then
		break
	elif [ "$status" = "False" ]; then
		die "PipelineRun $PRN failed — see $ART"
	elif [ "$(date +%s)" -ge "$deadline" ]; then
		die "PipelineRun $PRN timed out"
	fi
	sleep 5
done
log_kv step=e2e action=pipelinerun-succeeded run="$PRN"

# ---- assertions --------------------------------------------------------
echo
echo "e2e assertions:"

# resolve emitted the pinned APP_SHA
app_sha="$(kubectl -n "$NS" get taskrun -l tekton.dev/pipelineTask=resolve -o jsonpath='{.items[0].status.results[?(@.name=="app-sha")].value}' 2>/dev/null || true)"
check "resolve app-sha == pinned fixture SHA" test "$app_sha" = "$FIXTURE_SHA"

# assemble emitted a tag + a well-formed digest
img_tag="$(kubectl -n "$NS" get taskrun -l tekton.dev/pipelineTask=assemble -o jsonpath='{.items[0].status.results[?(@.name=="image-tag")].value}' 2>/dev/null || true)"
img_digest="$(kubectl -n "$NS" get taskrun -l tekton.dev/pipelineTask=assemble -o jsonpath='{.items[0].status.results[?(@.name=="image-digest")].value}' 2>/dev/null || true)"
check "assemble image-tag == cv:git-<sha>" test "$img_tag" = "$IMAGE_TAG"
check "assemble image-digest is sha256:<64hex>" bash -c "printf '%s' '$img_digest' | grep -Eqx 'sha256:[0-9a-f]{64}'"

# the built image is in the local store
check "built image present in the OrbStack store" docker image inspect "$IMAGE_TAG"

# the cv Deployment is by the tag, Never, ready, and its pod runs that image
dep_image="$(kubectl -n "$NS" get deploy/cv -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
dep_policy="$(kubectl -n "$NS" get deploy/cv -o jsonpath='{.spec.template.spec.containers[0].imagePullPolicy}' 2>/dev/null || true)"
dep_ready="$(kubectl -n "$NS" get deploy/cv -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
check "Deployment image == the assemble tag" test "$dep_image" = "$IMAGE_TAG"
check "Deployment imagePullPolicy == Never" test "$dep_policy" = "Never"
check "Deployment 1/1 ready" test "$dep_ready" = "1"
case "$dep_image" in
	*@sha256:*) is_digest_ref=yes ;;
	*) is_digest_ref=no ;;
esac
check "Deployment image is NOT an @sha256 ref (OrbStack constraint)" test "$is_digest_ref" = "no"

pod_imageid="$(kubectl -n "$NS" get pod -l app=cv -o jsonpath='{.items[0].status.containerStatuses[0].imageID}' 2>/dev/null || true)"
local_id="$(docker image inspect "$IMAGE_TAG" --format '{{.Id}}' 2>/dev/null | sed 's/^sha256://' || true)"
case "$pod_imageid" in
	*"$local_id"*) pod_matches=yes ;;
	*) pod_matches=no ;;
esac
check "running Pod imageID matches the local image ID" test "$pod_matches" = yes

# the deployed app actually serves
code="$(kubectl -n "$NS" run e2e-probe --image="$UTILS_IMAGE" --restart=Never --rm -i --quiet --timeout=60s --command -- \
	curl -s -o /dev/null -m 10 -w '%{http_code}' "http://cv.${NS}.svc.cluster.local/healthz" 2>/dev/null || true)"
check "deployed /healthz returns 200" test "$code" = "200"

# the deploy-state pointer ConfigMap
cm="$(kubectl -n "$NS" get cm cv-deploy-state -o jsonpath='{.data.current_digest}/{.data.app_sha}/{.data.current_tag}' 2>/dev/null || true)"
check "cv-deploy-state ConfigMap records digest+sha+tag" test "$cm" = "${img_digest}/${FIXTURE_SHA}/${IMAGE_TAG}"

# smoke left nothing behind
leftover="$(kubectl -n "$NS" get deploy,svc -l 'cv-oci/smoke' -o name 2>/dev/null | wc -l | tr -d ' ')"
check "no run-scoped smoke resources leaked" test "$leftover" = "0"

echo
if [ "$FAILURES" -eq 0 ]; then
	log_kv step=e2e result=PASS run="$PRN"
else
	die "e2e: $FAILURES assertion(s) failed — evidence in $ART"
fi
