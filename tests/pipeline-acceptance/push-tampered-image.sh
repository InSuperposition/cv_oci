#!/usr/bin/env bash
# push-tampered-image.sh — copy the signed build image, mutate one annotation
# (changing its digest), and cosign verify the mutated copy. The verify MUST
# fail: a byte-mutated image is no longer covered by the Chains signature.
#
#   NS   namespace of the PipelineRun `run`
#
# The chainsaw step asserts `check: ($error != null): true` — this script is
# expected to exit non-zero on the final cosign verify.
set -euo pipefail

: "${NS:?set NS}"
_here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/_resources/lib.sh
. "$_here/../_resources/lib.sh"
cd "$(cv_repo_root)"
zot=$(cv_zot)
repo="${zot}/${NS}"

digest=$(kubectl -n "$NS" get pipelinerun run \
	-o jsonpath='{.status.results[?(@.name=="app-image-digest")].value}')

tampered="${repo}:tampered"
crane copy --insecure "${repo}@${digest}" "$tampered" >/dev/null
crane mutate --insecure "$tampered" --annotation cv-oci.test=tamper -t "$tampered" >/dev/null
tdig=$(crane digest --insecure "$tampered")

pub=$(mktemp)
trap 'rm -f "$pub"' EXIT
cv_chains_pubkey "$pub"
cosign verify --key "$pub" --insecure-ignore-tlog=true --allow-insecure-registry "${repo}@${tdig}"
