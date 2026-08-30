#!/usr/bin/env bash
# negative.sh — prove the Slice 1 pipeline FAILS where it should, and cleans up.
#
# Scenario 1  bad ref              -> `resolve` fails, nothing else runs
# Scenario 2  pre-/healthz commit  -> build+assemble pass, `smoke` fails on
#                                     GET /healthz, `deploy` is skipped, and the
#                                     smoke teardown still runs (no leak)
#
# The third design-doc case (degenerate release tree) is covered at the unit
# level by scripts/test/assert-trees.bats — injecting a broken tree into the
# real build Task would need a test-only prod code path (Goodhart), so it is
# asserted where the guard actually lives.
#
# Needs: kubectl, tkn, jq. Run after bootstrap.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=scripts/lib/log.sh
source "$ROOT/scripts/lib/log.sh"
cd "$ROOT"
need kubectl; need tkn

# shellcheck disable=SC1091
source digests.env
UTILS_IMAGE="cv/pipeline-utils:slice1-arm64"
BUILD_IMAGE="docker.io/library/node:24-bookworm-slim@${NODEBUILD}"
DISTROLESS="gcr.io/distroless/nodejs24-debian12@${DISTROLESSNODE}"
OCI_REPO_URL="${CV_OCI_REPO:-https://github.com/InSuperposition/cv_oci}"
OCI_REF="${CV_OCI_REF:-main}"
PRE_HEALTHZ_SHA="0bbc68418ce92048a85b8b18afe1dcfe6204bb83"   # cv_frontend "Initial commit"

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
empty() { [ -z "$1" ]; }
nonempty_not() { [ -n "$1" ] && [ "$1" != "$2" ]; }

UID_SUFFIX="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
NS="cv-neg-${UID_SUFFIX}"
cleanup() {
	local rc=$?
	kubectl delete ns "$NS" --wait=false >/dev/null 2>&1 || true
	docker rmi "cv:git-${PRE_HEALTHZ_SHA}" >/dev/null 2>&1 || true
	exit $rc
}
trap cleanup EXIT

kubectl create ns "$NS" >/dev/null
sed "s/namespace: cv-pipeline/namespace: $NS/" manifests/rbac.yaml | kubectl apply -f - >/dev/null
kubectl -n "$NS" apply -f tasks/ -f pipeline/ >/dev/null

run_pipeline() { # run_pipeline <frontend-ref>  -> prints the PipelineRun name
	kubectl -n "$NS" create -o name -f - <<EOF | sed 's#.*/##'
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata: { generateName: neg- }
spec:
  pipelineRef: { name: cv-slice1 }
  taskRunTemplate:
    serviceAccountName: cv-pipeline-sa
    podTemplate: { securityContext: { fsGroup: 65532 } }
  params:
    - { name: utils-image, value: "$UTILS_IMAGE" }
    - { name: build-image, value: "$BUILD_IMAGE" }
    - { name: distroless-base, value: "$DISTROLESS" }
    - { name: frontend-repo, value: "$FRONTEND_REPO" }
    - { name: frontend-ref, value: "$1" }
    - { name: oci-repo, value: "$OCI_REPO_URL" }
    - { name: oci-ref, value: "$OCI_REF" }
    - { name: namespace, value: "$NS" }
  workspaces:
    - name: shared
      volumeClaimTemplate:
        spec: { accessModes: [ReadWriteOnce], resources: { requests: { storage: 3Gi } } }
EOF
}

wait_done() { # wait_done <prn>  -> prints True|False
	local prn="$1" deadline
	deadline=$(( $(date +%s) + 600 ))
	while :; do
		local s
		s="$(kubectl -n "$NS" get pipelinerun "$prn" -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || true)"
		if [ "$s" = "True" ] || [ "$s" = "False" ]; then printf '%s' "$s"; return; fi
		if [ "$(date +%s)" -ge "$deadline" ]; then printf 'timeout'; return; fi
		sleep 5
	done
}

task_status() { # task_status <prn> <pipelineTask>
	kubectl -n "$NS" get taskrun \
		-l "tekton.dev/pipelineRun=$1,tekton.dev/pipelineTask=$2" \
		-o jsonpath='{.items[0].status.conditions[0].reason}' 2>/dev/null || true
}

# ---- scenario 1: bad ref ------------------------------------------------
log_kv step=negative scenario=bad-ref
p1="$(run_pipeline "no-such-branch-xyz-$UID_SUFFIX")"
r1="$(wait_done "$p1")"
check "bad ref: PipelineRun failed"           test "$r1" = "False"
check "bad ref: resolve did not succeed"      nonempty_not "$(task_status "$p1" resolve)" Succeeded
check "bad ref: build never ran"              empty "$(task_status "$p1" build)"

# ---- scenario 2: pre-/healthz commit ----------------------------------
log_kv step=negative scenario=pre-healthz sha="$PRE_HEALTHZ_SHA"
p2="$(run_pipeline "$PRE_HEALTHZ_SHA")"
r2="$(wait_done "$p2")"
check "pre-healthz: PipelineRun failed"       test "$r2" = "False"
check "pre-healthz: build succeeded"          test "$(task_status "$p2" build)" = "Succeeded"
check "pre-healthz: assemble succeeded"       test "$(task_status "$p2" assemble)" = "Succeeded"
check "pre-healthz: smoke failed"             nonempty_not "$(task_status "$p2" smoke)" Succeeded
check "pre-healthz: deploy was skipped"       empty "$(task_status "$p2" deploy)"
check "pre-healthz: smoke-teardown ran"       test "$(task_status "$p2" smoke-teardown)" = "Succeeded"
check "pre-healthz: no smoke resources leaked" test "$(kubectl -n "$NS" get deploy,svc -l cv-oci/smoke -o name 2>/dev/null | wc -l | tr -d ' ')" = "0"
check "pre-healthz: nothing deployed to cv"   empty "$(kubectl -n "$NS" get deploy cv -o name 2>/dev/null || true)"

echo
if [ "$FAILURES" -eq 0 ]; then
	log_kv step=negative result=PASS
else
	die "negative: $FAILURES assertion(s) failed"
fi
