#!/usr/bin/env bash
# negative.sh — prove the pipeline (cv-build) FAILS where it should.
#
# Scenario 1  bad ref              -> `fetch` fails, nothing downstream runs
# Scenario 2  pre-/healthz commit  -> `fetch` + `build` pass, `smoke` fails on
#                                     GET /healthz, `deploy` is skipped, the
#                                     `finally` smoke-teardown still runs, and
#                                     nothing is deployed to `cv` (no leak)
# Scenario 3  CVE gate             -> the exact scan-step policy, run against a
#                                     frozen fixture SBOM with a known fixable
#                                     CRITICAL, exits non-zero (the gate blocks)
#
# Needs: kubectl, tkn, crane, trivy. Run after bootstrap.sh (zot up, node-trust done).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=scripts/lib/log.sh
source "$ROOT/scripts/lib/log.sh"
cd "$ROOT"
need kubectl; need tkn; need crane; need trivy

# shellcheck disable=SC1091
source digests.env
ZOT_ADDR="${CV_ZOT_ADDR:-zot.cv-pipeline.svc.cluster.local:5000}"
BUILDER="docker.io/heroku/builder:24@${CNBBUILDER}"
RUN_IMAGE="docker.io/heroku/heroku:24@${CNBRUNIMAGE}"
UTILITY="docker.io/library/bash@${CNBUTILITYIMAGE}"
KUBECTL_IMG="docker.io/alpine/k8s:1.31.1@${CNBKUBECTLIMAGE}"
GIT_IMG="docker.io/alpine/git@${CNBGITIMAGE}"
TRIVY_IMG="ghcr.io/aquasecurity/trivy@${TRIVYCLI}"
ORAS_IMG="ghcr.io/oras-project/oras@${ORASCLI}"
TRIVY_DB="${TRIVYDB}"
PRE_HEALTHZ_SHA="0bbc68418ce92048a85b8b18afe1dcfe6204bb83"   # cv_frontend "Initial commit"

FAILURES=0
check() { local label="$1"; shift
	if "$@" >/dev/null 2>&1; then printf '  PASS  %s\n' "$label"
	else printf '  FAIL  %s\n' "$label"; FAILURES=$((FAILURES + 1)); fi
}
empty() { [ -z "$1" ]; }
nonempty_not() { [ -n "$1" ] && [ "$1" != "$2" ]; }

UID_SUFFIX="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
NS="cv-neg-${UID_SUFFIX}"
ZOT_REPO="${ZOT_ADDR}/cv-neg-${UID_SUFFIX}"
cleanup() {
	local rc=$?
	kubectl delete ns "$NS" --wait=false >/dev/null 2>&1 || true
	# best-effort: drop any run-scoped zot tag (the zot image has no shell, so
	# `kubectl exec -- rm` is not an option — use the registry API). Only the
	# pre-/healthz scenario pushes a tag; the bad-ref one fails before build.
	crane delete --insecure "${ZOT_REPO}:git-${PRE_HEALTHZ_SHA}" >/dev/null 2>&1 || true
	exit $rc
}
trap cleanup EXIT

kubectl create ns "$NS" >/dev/null
# Match cv-pipeline's PSA level so the run really exercises `restricted` (Slice 1.7).
kubectl label ns "$NS" \
	pod-security.kubernetes.io/enforce=restricted \
	pod-security.kubernetes.io/enforce-version=latest >/dev/null
sed "s/namespace: cv-pipeline/namespace: $NS/" manifests/rbac.yaml | kubectl apply -f - >/dev/null
kubectl -n "$NS" apply -f tasks/buildpacks.yaml -f pipeline/pipeline.yaml >/dev/null

run_pipeline() { # run_pipeline <frontend-ref>  -> prints the PipelineRun name
	kubectl -n "$NS" create -o name -f - <<EOF | sed 's#.*/##'
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata: { generateName: neg- }
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
    - { name: trivy-image, value: "$TRIVY_IMG" }
    - { name: oras-image, value: "$ORAS_IMG" }
    - { name: trivy-db, value: "$TRIVY_DB" }
    - { name: frontend-repo, value: "$FRONTEND_REPO" }
    - { name: frontend-ref, value: "$1" }
    - { name: app-repo, value: "${ZOT_ADDR}/cv-neg-${UID_SUFFIX}" }
    - { name: namespace, value: "$NS" }
  workspaces:
    - name: shared
      volumeClaimTemplate:
        spec: { accessModes: [ReadWriteOnce], resources: { requests: { storage: 3Gi } } }
  timeouts: { pipeline: 25m }
EOF
}

wait_done() { # wait_done <prn>  -> prints True|False|timeout
	local prn="$1" deadline
	deadline=$(( $(date +%s) + 1200 ))
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
check "bad ref: PipelineRun failed"      test "$r1" = "False"
check "bad ref: fetch did not succeed"   nonempty_not "$(task_status "$p1" fetch)" Succeeded
check "bad ref: build never ran"         empty "$(task_status "$p1" build)"

# ---- scenario 2: pre-/healthz commit ----------------------------------
log_kv step=negative scenario=pre-healthz sha="$PRE_HEALTHZ_SHA"
p2="$(run_pipeline "$PRE_HEALTHZ_SHA")"
r2="$(wait_done "$p2")"
check "pre-healthz: PipelineRun failed"        test "$r2" = "False"
check "pre-healthz: build succeeded"           test "$(task_status "$p2" build)" = "Succeeded"
check "pre-healthz: smoke failed"              nonempty_not "$(task_status "$p2" smoke)" Succeeded
check "pre-healthz: deploy was skipped"        empty "$(task_status "$p2" deploy)"
check "pre-healthz: smoke-teardown ran"        test "$(task_status "$p2" smoke-teardown)" = "Succeeded"
check "pre-healthz: no smoke resources leaked" test "$(kubectl -n "$NS" get deploy,svc -l cv-oci/smoke -o name 2>/dev/null | wc -l | tr -d ' ')" = "0"
check "pre-healthz: nothing deployed to cv"    empty "$(kubectl -n "$NS" get deploy cv -o name 2>/dev/null || true)"

# ---- scenario 3: CVE gate blocks a fixable CRITICAL --------------------
# The scan step's policy string, kept in sync here (grep guard below). Running
# it against a frozen fixture SBOM (lodash@4.17.4, CVE-2019-10744 CRITICAL,
# fixed in 4.17.12) with the digest-pinned DB is a permanently reproducible
# FAIL — no vuln image to pull, no drift.
log_kv step=negative scenario=cve-gate
POLICY="--severity CRITICAL --ignore-unfixed --exit-code 1"
check "scan-step policy string matches pipeline.yaml" \
	grep -qF -- "POLICY=\"$POLICY\"" pipeline/pipeline.yaml
set +e
# shellcheck disable=SC2086
trivy sbom scripts/test/fixtures/vuln-sbom.cdx.json --quiet \
	--db-repository "ghcr.io/aquasecurity/trivy-db@${TRIVY_DB}" $POLICY >/dev/null 2>&1
cve_rc=$?
set -e
check "CVE gate exits non-zero on the fixable-CRITICAL fixture" test "$cve_rc" -ne 0

echo
if [ "$FAILURES" -eq 0 ]; then
	log_kv step=negative result=PASS
else
	die "negative: $FAILURES assertion(s) failed"
fi
