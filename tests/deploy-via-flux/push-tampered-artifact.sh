#!/usr/bin/env bash
# push-tampered-artifact.sh — copy the currently-verified cv-frontend artifact,
# mutate it, and push it at a strictly-higher CalVer tag (so the semver
# resolver would pick it). Cleans up the tamper tags and forces one more
# reconcile regardless of outcome.
#
#   {"seen_verification_failure":bool,"revision_unchanged":bool}
#
# The chainsaw assert: tree checks both are true — the OCIRepository MUST flag
# a verification failure and MUST NOT adopt the tampered digest.
set -euo pipefail

repo="zot.cv-pipeline.svc.cluster.local:5000/cv-frontend"
bad="0.99999999.0"

before=$(kubectl -n flux-system get ocirepository cv-frontend -o jsonpath='{.status.artifact.revision}')
before_dig=${before#*@}

cleanup() {
	crane delete --insecure "${repo}:${bad}" >/dev/null 2>&1 || true
	crane delete --insecure "${repo}:__tamper_src" >/dev/null 2>&1 || true
	kubectl -n flux-system annotate --overwrite ocirepository/cv-frontend \
		reconcile.fluxcd.io/requestedAt="$(date +%s)" >/dev/null 2>&1 || true
}
trap cleanup EXIT

crane copy --insecure "${repo}@${before_dig}" "${repo}:__tamper_src" >/dev/null
crane mutate --insecure "${repo}:__tamper_src" --annotation cv-oci.test=tamper -t "${repo}:${bad}" >/dev/null
kubectl -n flux-system annotate --overwrite ocirepository/cv-frontend \
	reconcile.fluxcd.io/requestedAt="$(date +%s)" >/dev/null 2>&1 || true

deadline=$(( $(date +%s) + 240 ))
seen=false
while :; do
	msg=$(kubectl -n flux-system get ocirepository cv-frontend \
		-o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || true)
	case "$msg" in *erif*|*signature*) seen=true; break ;; esac
	[ "$(date +%s)" -ge "$deadline" ] && break
	sleep 10
done

now=$(kubectl -n flux-system get ocirepository cv-frontend -o jsonpath='{.status.artifact.revision}')

jq -nc --argjson seen "$seen" --argjson unchanged "$([ "$now" = "$before" ] && echo true || echo false)" \
	'{seen_verification_failure: $seen, revision_unchanged: $unchanged}'
