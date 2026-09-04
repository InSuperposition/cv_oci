#!/usr/bin/env bash
# read-task-reasons.sh — guard that this run's build / smoke / smoke-teardown
# TaskRuns ended as the pre-/healthz scenario requires: build Succeeded, smoke
# NOT Succeeded (no /healthz route), teardown Succeeded.
#
#   NS   the namespace the PipelineRun `run` lives in
#
# T4a asserts here; T4b makes this print {"build":..,"smoke":..,"teardown":..}
# and moves the checks to a chainsaw assert: tree.
set -euo pipefail

: "${NS:?set NS}"

reason() {
	kubectl -n "$NS" get taskrun \
		-l "tekton.dev/pipelineTask=$1,tekton.dev/pipelineRun=run" \
		-o jsonpath='{.items[0].status.conditions[0].reason}' 2>/dev/null || true
}

build=$(reason build)
smoke=$(reason smoke)
teardown=$(reason smoke-teardown)

[ "$build" = "Succeeded" ] || { echo "build=$build" >&2; exit 1; }
[ -n "$smoke" ] && [ "$smoke" != "Succeeded" ] || { echo "smoke=$smoke" >&2; exit 1; }
[ "$teardown" = "Succeeded" ] || { echo "teardown=$teardown" >&2; exit 1; }
