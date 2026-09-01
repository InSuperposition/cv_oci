#!/usr/bin/env bash
# e2e.sh — the executable acceptance test for the pipeline (cv-build).
#
# Runs the real cv-build Pipeline against the live OrbStack cluster with the
# pinned cv_frontend fixture SHA, in a unique throwaway namespace. Pushes to a
# run-scoped repo in the shared zot so it never clobbers the real `cv` image.
# Captures run evidence before teardown, asserts the full success contract
# (deploy BY @sha256 from zot), and
# cleans up even if an assertion fails.
#
#   scripts/test/e2e.sh          happy path
#   scripts/test/e2e.sh --keep   leave the namespace + artifacts + zot repo
#
# Needs: kubectl, tkn, crane, jq (host tools). zot must be up in cv-pipeline
# (bootstrap/bootstrap.sh) and the OrbStack node-trust steps done (runbook.md).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=scripts/lib/log.sh
source "$ROOT/scripts/lib/log.sh"
cd "$ROOT"
need kubectl; need tkn; need crane; need jq

KEEP=0
[ "${1:-}" = "--keep" ] && KEEP=1

# shellcheck disable=SC1091
source digests.env
FIXTURE_SHA="$FRONTEND_FIXTURE_SHA"
FRONTEND_REPO_URL="$FRONTEND_REPO"
ZOT_ADDR="${CV_ZOT_ADDR:-zot.cv-pipeline.svc.cluster.local:5000}"

BUILDER="docker.io/heroku/builder:24@${CNBBUILDER}"
RUN_IMAGE="docker.io/heroku/heroku:24@${CNBRUNIMAGE}"
UTILITY="docker.io/library/bash@${CNBUTILITYIMAGE}"
KUBECTL_IMG="docker.io/alpine/k8s:1.31.1@${CNBKUBECTLIMAGE}"
GIT_IMG="docker.io/alpine/git@${CNBGITIMAGE}"

UID_SUFFIX="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
NS="cv-e2e-${UID_SUFFIX}"
APP_REPO="${ZOT_ADDR}/cv-e2e-${UID_SUFFIX}"
ART="$ROOT/scripts/test/_artifacts/${NS}"
mkdir -p "$ART"

FAILURES=0
check() { local label="$1"; shift
	if "$@" >/dev/null 2>&1; then printf '  PASS  %s\n' "$label"
	else printf '  FAIL  %s\n' "$label"; FAILURES=$((FAILURES + 1)); fi
}

capture() {
	log_kv step=e2e action=capture-evidence dir="$ART"
	kubectl -n "$NS" get pipelinerun "$PRN" -o yaml   > "$ART/pipelinerun.yaml"   2>&1 || true
	kubectl -n "$NS" get taskruns -o yaml             > "$ART/taskruns.yaml"      2>&1 || true
	kubectl -n "$NS" get events --sort-by=.lastTimestamp > "$ART/events.txt"      2>&1 || true
	tkn -n "$NS" pipelinerun logs "$PRN"              > "$ART/pipeline.log"       2>&1 || true
	kubectl -n "$NS" get deploy,svc,cm,pods -o yaml   > "$ART/deployed.yaml"      2>&1 || true
}

cleanup() {
	local rc=$?
	[ -n "${PRN:-}" ] && capture
	if [ "$KEEP" -eq 1 ]; then
		log_kv step=e2e action=kept ns="$NS" repo="$APP_REPO" artifacts="$ART"
	else
		kubectl delete ns "$NS" --wait=false >/dev/null 2>&1 || true
		# best-effort: drop the run-scoped zot tag (the zot image has no shell,
		# so `kubectl exec -- rm` is not an option — use the registry API)
		crane delete --insecure "${APP_REPO}:git-${FIXTURE_SHA}" >/dev/null 2>&1 || true
		rm -rf "$ART"
	fi
	exit $rc
}
trap cleanup EXIT

log_kv step=e2e action=setup ns="$NS" fixture="$FIXTURE_SHA" repo="$APP_REPO"
kubectl create ns "$NS" >/dev/null
# Match cv-pipeline's PSA level so the run really exercises `restricted` (Slice 1.7).
kubectl label ns "$NS" \
	pod-security.kubernetes.io/enforce=restricted \
	pod-security.kubernetes.io/enforce-version=latest >/dev/null
sed "s/namespace: cv-pipeline/namespace: $NS/" manifests/rbac.yaml | kubectl apply -f - >/dev/null
kubectl -n "$NS" apply -f tasks/buildpacks.yaml -f pipeline/pipeline.yaml >/dev/null

PRN="$(kubectl -n "$NS" create -o name -f - <<EOF | sed 's#.*/##'
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata: { generateName: e2e- }
spec:
  pipelineRef: { name: cv-build }
  taskRunTemplate:
    serviceAccountName: cv-build-sa
    podTemplate:
      securityContext: { fsGroup: 1000 }
      nodeSelector: { kubernetes.io/arch: arm64 }
  taskRunSpecs:
    - { pipelineTaskName: smoke, serviceAccountName: cv-smoke-sa }
    - { pipelineTaskName: smoke-teardown, serviceAccountName: cv-smoke-sa }
    - { pipelineTaskName: deploy, serviceAccountName: cv-deploy-sa }
  params:
    - { name: builder-image, value: "$BUILDER" }
    - { name: run-image, value: "$RUN_IMAGE" }
    - { name: utility-image, value: "$UTILITY" }
    - { name: kubectl-image, value: "$KUBECTL_IMG" }
    - { name: git-image, value: "$GIT_IMG" }
    - { name: frontend-repo, value: "$FRONTEND_REPO_URL" }
    - { name: frontend-ref, value: "$FIXTURE_SHA" }
    - { name: app-repo, value: "$APP_REPO" }
    - { name: namespace, value: "$NS" }
  workspaces:
    - name: shared
      volumeClaimTemplate:
        spec: { accessModes: [ReadWriteOnce], resources: { requests: { storage: 3Gi } } }
  timeouts: { pipeline: 25m }
EOF
)"
log_kv step=e2e action=pipelinerun-started run="$PRN"

deadline=$(( $(date +%s) + 1200 ))
while :; do
	status="$(kubectl -n "$NS" get pipelinerun "$PRN" -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || true)"
	if [ "$status" = "True" ]; then break
	elif [ "$status" = "False" ]; then die "PipelineRun $PRN failed — see $ART"
	elif [ "$(date +%s)" -ge "$deadline" ]; then die "PipelineRun $PRN timed out"
	fi
	sleep 5
done
log_kv step=e2e action=pipelinerun-succeeded run="$PRN"

echo
echo "e2e assertions:"

digest="$(kubectl -n "$NS" get pipelinerun "$PRN" -o jsonpath='{.status.results[?(@.name=="app-image-digest")].value}' 2>/dev/null || true)"
check "pipeline app-image-digest is sha256:<64hex>" bash -c "printf '%s' '$digest' | grep -Eqx 'sha256:[0-9a-f]{64}'"

want_ref="${APP_REPO}@${digest}"
dep_image="$(kubectl -n "$NS" get deploy/cv -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
dep_policy="$(kubectl -n "$NS" get deploy/cv -o jsonpath='{.spec.template.spec.containers[0].imagePullPolicy}' 2>/dev/null || true)"
dep_ready="$(kubectl -n "$NS" get deploy/cv -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
check "Deployment image == <zot>/cv-e2e@sha256:<digest>" test "$dep_image" = "$want_ref"
case "$dep_image" in *@sha256:*) is_digest=yes ;; *) is_digest=no ;; esac
check "Deployment image IS an @sha256 ref" test "$is_digest" = "yes"
check "Deployment imagePullPolicy == IfNotPresent" test "$dep_policy" = "IfNotPresent"
check "Deployment 1/1 ready" test "$dep_ready" = "1"

pod_imageid="$(kubectl -n "$NS" get pod -l app=cv -o jsonpath='{.items[0].status.containerStatuses[0].imageID}' 2>/dev/null || true)"
case "$pod_imageid" in *"$digest"*) pod_matches=yes ;; *) pod_matches=no ;; esac
check "running Pod imageID carries the built digest" test "$pod_matches" = yes

check "the image is really in zot" crane digest --insecure "$want_ref"

# The probe pod needs its own restricted securityContext — $NS enforces PSA
# `restricted` (Slice 1.7). Strategic-merge it onto the generated e2e-probe container.
PROBE_SC='{"spec":{"containers":[{"name":"e2e-probe","securityContext":{"runAsNonRoot":true,"runAsUser":1000,"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"seccompProfile":{"type":"RuntimeDefault"}}}]}}'
code="$(kubectl -n "$NS" run e2e-probe --image="$KUBECTL_IMG" --restart=Never --rm -i --quiet --timeout=60s \
	--override-type=strategic --overrides="$PROBE_SC" --command -- \
	curl -s -o /dev/null -m 10 -w '%{http_code}' "http://cv.${NS}.svc.cluster.local/healthz" 2>/dev/null || true)"
check "deployed /healthz returns 200" test "$code" = "200"

cm="$(kubectl -n "$NS" get cm cv-deploy-state -o jsonpath='{.data.current_digest}/{.data.app_sha}' 2>/dev/null || true)"
check "cv-deploy-state records digest + app-sha" test "$cm" = "${digest}/${FIXTURE_SHA}"
cm_pr="$(kubectl -n "$NS" get cm cv-deploy-state -o jsonpath='{.data.pipelinerun}' 2>/dev/null || true)"
check "cv-deploy-state records the PipelineRun" test "$cm_pr" = "$PRN"

leftover="$(kubectl -n "$NS" get deploy,svc -l 'cv-oci/smoke' -o name 2>/dev/null | wc -l | tr -d ' ')"
check "no run-scoped smoke resources leaked" test "$leftover" = "0"

echo
if [ "$FAILURES" -eq 0 ]; then
	log_kv step=e2e result=PASS run="$PRN"
else
	die "e2e: $FAILURES assertion(s) failed — evidence in $ART"
fi
