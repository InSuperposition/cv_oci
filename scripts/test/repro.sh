#!/usr/bin/env bash
# repro.sh — the executable reproducibility test for the pipeline (cv-build).
#
# Slice 2 (docs/designs/buildpacks-pivot.md): build the pinned cv_frontend
# fixture SHA twice, independently — separate throwaway namespaces, separate
# zot repos, no shared cache — and assert the CNB lifecycle's own
# content-addressed layer hashes agree between the two builds:
#
#   - the app layer's diffID   (io.buildpacks.lifecycle.metadata.app[].sha)
#   - the SBOM layer's diffID  (io.buildpacks.lifecycle.metadata.sbom.sha)
#
# These are the lifecycle's own sha256 of each CNB layer's *uncompressed*
# tar content — a real content hash, immune to gzip/manifest-ordering noise.
# That is what "assert equal SBOM package set + equal app-layer content hash,
# not raw digest" (buildpacks-pivot.md Success Criteria) means in practice: the
# lifecycle already publishes exactly this pair of hashes in a well-known
# image label, so there is no need to hand-roll tar normalization.
#
# As a bonus, non-load-bearing check, this also asserts the two outer image
# digests match: as of this test, the build is fully byte-reproducible (see
# docs/debt.md — the app layer's only nondeterminism source was our own
# fetch step leaving a `.git` dir for the buildpack to copy in, fixed in
# pipeline/pipeline.yaml). If a future lifecycle/builder bump reintroduces
# outer-digest drift without changing app/SBOM content, this check is the one
# expected to go red first — it is deliberately not what PASS depends on.
#
#   scripts/test/repro.sh          happy path
#   scripts/test/repro.sh --keep   leave both namespaces + artifacts
#
# Needs: kubectl, tkn, crane, jq. zot must be up in cv-pipeline (bootstrap.sh)
# and the OrbStack node-trust steps done (docs/runbook.md).
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
ZOT_ADDR="${CV_ZOT_ADDR:-zot.cv-pipeline.svc.cluster.local:5000}"

BUILDER="docker.io/heroku/builder:24@${CNBBUILDER}"
RUN_IMAGE="docker.io/heroku/heroku:24@${CNBRUNIMAGE}"
UTILITY="docker.io/library/bash@${CNBUTILITYIMAGE}"
KUBECTL_IMG="docker.io/alpine/k8s:1.31.1@${CNBKUBECTLIMAGE}"
GIT_IMG="docker.io/alpine/git@${CNBGITIMAGE}"

UID_SUFFIX="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
NS1="cv-repro-${UID_SUFFIX}-1"
NS2="cv-repro-${UID_SUFFIX}-2"
APP_REPO1="${ZOT_ADDR}/cv-repro-${UID_SUFFIX}-1"
APP_REPO2="${ZOT_ADDR}/cv-repro-${UID_SUFFIX}-2"
ART="$ROOT/scripts/test/_artifacts/cv-repro-${UID_SUFFIX}"
mkdir -p "$ART"

FAILURES=0
check() { local label="$1"; shift
	if "$@" >/dev/null 2>&1; then printf '  PASS  %s\n' "$label"
	else printf '  FAIL  %s\n' "$label"; FAILURES=$((FAILURES + 1)); fi
}

capture() { # capture <n> <ns> <prn>
	kubectl -n "$2" get pipelinerun "$3" -o yaml > "$ART/pipelinerun-$1.yaml" 2>&1 || true
	tkn -n "$2" pipelinerun logs "$3"          > "$ART/pipeline-$1.log"     2>&1 || true
}

cleanup() {
	local rc=$?
	[ -n "${PRN1:-}" ] && capture 1 "$NS1" "$PRN1"
	[ -n "${PRN2:-}" ] && capture 2 "$NS2" "$PRN2"
	if [ "$KEEP" -eq 1 ]; then
		log_kv step=repro action=kept ns1="$NS1" ns2="$NS2" artifacts="$ART"
	else
		kubectl delete ns "$NS1" "$NS2" --wait=false >/dev/null 2>&1 || true
		rm -rf "$ART"
	fi
	exit $rc
}
trap cleanup EXIT

start_build() { # start_build <n> <ns> <app-repo>  -> prints the PipelineRun name
	kubectl -n "$2" create -o name -f - <<EOF | sed 's#.*/##'
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata: { generateName: repro-$1- }
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
    - { name: frontend-repo, value: "$FRONTEND_REPO" }
    - { name: frontend-ref, value: "$FIXTURE_SHA" }
    - { name: app-repo, value: "$3" }
    - { name: namespace, value: "$2" }
  workspaces:
    - name: shared
      volumeClaimTemplate:
        spec: { accessModes: [ReadWriteOnce], resources: { requests: { storage: 3Gi } } }
  timeouts: { pipeline: 25m }
EOF
}

wait_done() { # wait_done <ns> <prn>  -> prints True|False|timeout
	local ns="$1" prn="$2" deadline
	deadline=$(( $(date +%s) + 1200 ))
	while :; do
		local s
		s="$(kubectl -n "$ns" get pipelinerun "$prn" -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || true)"
		if [ "$s" = "True" ] || [ "$s" = "False" ]; then printf '%s' "$s"; return; fi
		if [ "$(date +%s)" -ge "$deadline" ]; then printf 'timeout'; return; fi
		sleep 5
	done
}

seed_ns() { # seed_ns <ns>
	kubectl create ns "$1" >/dev/null
	sed "s/namespace: cv-pipeline/namespace: $1/" manifests/rbac.yaml | kubectl apply -f - >/dev/null
	kubectl -n "$1" apply -f tasks/buildpacks.yaml -f pipeline/pipeline.yaml >/dev/null
}

log_kv step=repro action=setup fixture="$FIXTURE_SHA" ns1="$NS1" ns2="$NS2"
seed_ns "$NS1"
seed_ns "$NS2"

PRN1="$(start_build 1 "$NS1" "$APP_REPO1")"
PRN2="$(start_build 2 "$NS2" "$APP_REPO2")"
log_kv step=repro action=builds-started run1="$PRN1" run2="$PRN2"

r1="$(wait_done "$NS1" "$PRN1")"
r2="$(wait_done "$NS2" "$PRN2")"
[ "$r1" = "True" ] || die "build 1 ($PRN1) did not succeed: $r1 — see $ART"
[ "$r2" = "True" ] || die "build 2 ($PRN2) did not succeed: $r2 — see $ART"
log_kv step=repro action=builds-succeeded run1="$PRN1" run2="$PRN2"

digest1="$(kubectl -n "$NS1" get pipelinerun "$PRN1" -o jsonpath='{.status.results[?(@.name=="app-image-digest")].value}')"
digest2="$(kubectl -n "$NS2" get pipelinerun "$PRN2" -o jsonpath='{.status.results[?(@.name=="app-image-digest")].value}')"

cfg1="$(crane config --insecure "${APP_REPO1}@${digest1}")"
cfg2="$(crane config --insecure "${APP_REPO2}@${digest2}")"
meta1="$(jq -r '.config.Labels["io.buildpacks.lifecycle.metadata"]' <<<"$cfg1")"
meta2="$(jq -r '.config.Labels["io.buildpacks.lifecycle.metadata"]' <<<"$cfg2")"
app_sha1="$(jq -r '.app[0].sha' <<<"$meta1")"
app_sha2="$(jq -r '.app[0].sha' <<<"$meta2")"
sbom_sha1="$(jq -r '.sbom.sha' <<<"$meta1")"
sbom_sha2="$(jq -r '.sbom.sha' <<<"$meta2")"

echo
echo "reproducibility assertions:"
check "app-layer content hash matches across two independent builds"  test "$app_sha1" = "$app_sha2"
check "SBOM layer content hash matches across two independent builds" test "$sbom_sha1" = "$sbom_sha2"
check "(bonus) outer image digest matches"                            test "$digest1" = "$digest2"

echo
if [ "$FAILURES" -eq 0 ]; then
	log_kv step=repro result=PASS app_sha="$app_sha1" sbom_sha="$sbom_sha1"
else
	die "repro: $FAILURES assertion(s) failed — evidence in $ART"
fi
