#!/usr/bin/env bash
# read-pipeline-results.sh — the deploy TaskRun's Chains-signable manifest pair
# (bare URL + sha256, P11b) plus the PipelineRun's app-image-digest, for the
# fixed PipelineRun `deploy-via-flux-run` in cv-pipeline.
#
#   {"url":..,"digest":"sha256:..","app_digest":"sha256:.."}
#
# The chainsaw assert: tree checks the url/digest shape and, later in the
# suite, that the deployed cv Deployment's image carries app_digest.
set -euo pipefail

pr_result() {
	kubectl -n cv-pipeline get pipelinerun deploy-via-flux-run \
		-o jsonpath="{.status.results[?(@.name=='$1')].value}"
}
tr_result() {
	kubectl -n cv-pipeline get taskrun \
		-l "tekton.dev/pipelineTask=deploy,tekton.dev/pipelineRun=deploy-via-flux-run" \
		-o jsonpath="{.items[0].status.results[?(@.name=='$1')].value}"
}

jq -nc \
	--arg url "$(tr_result manifests_IMAGE_URL)" \
	--arg digest "$(tr_result manifests_IMAGE_DIGEST)" \
	--arg app_digest "$(pr_result app-image-digest)" \
	'{url:$url, digest:$digest, app_digest:$app_digest}'
