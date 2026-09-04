#!/usr/bin/env bash
# read-fetch-taskrun-reason.sh — the condition reason of this run's `fetch`
# TaskRun. A bogus git ref must make `fetch` end non-Succeeded and nothing
# downstream may run.
#
#   NS   the namespace the PipelineRun `run` lives in
#
# T3a (extraction): asserts the reason is present and not "Succeeded".
# T3b converts the assertion to a chainsaw assert: tree.
set -euo pipefail

: "${NS:?set NS}"

reason=$(kubectl -n "$NS" get taskrun \
	-l tekton.dev/pipelineTask=fetch,tekton.dev/pipelineRun=run \
	-o jsonpath='{.items[0].status.conditions[0].reason}')

[ -n "$reason" ] && [ "$reason" != "Succeeded" ] || {
	echo "fetch reason=$reason (expected a non-Succeeded terminal reason)" >&2
	exit 1
}
