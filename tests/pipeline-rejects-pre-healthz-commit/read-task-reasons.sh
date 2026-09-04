#!/usr/bin/env bash
# read-task-reasons.sh — print the condition reason of this run's build / smoke
# / smoke-teardown TaskRuns as JSON. The pre-/healthz commit builds fine but has
# no /healthz route, so the chainsaw assert: tree checks: build Succeeded, smoke
# NOT Succeeded, teardown Succeeded.
#
#   NS   the namespace the PipelineRun `run` lives in
#
#   {"build":"Succeeded","smoke":"Failed","teardown":"Succeeded"}
set -euo pipefail

: "${NS:?set NS}"

reason() {
	kubectl -n "$NS" get taskrun \
		-l "tekton.dev/pipelineTask=$1,tekton.dev/pipelineRun=run" \
		-o jsonpath='{.items[0].status.conditions[0].reason}' 2>/dev/null || true
}

jq -nc \
	--arg b "$(reason build)" \
	--arg s "$(reason smoke)" \
	--arg t "$(reason smoke-teardown)" \
	'{build: $b, smoke: $s, teardown: $t}'
