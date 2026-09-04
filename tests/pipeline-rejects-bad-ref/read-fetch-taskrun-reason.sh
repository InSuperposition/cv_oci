#!/usr/bin/env bash
# read-fetch-taskrun-reason.sh — print the condition reason of this run's
# `fetch` TaskRun as JSON. A bogus git ref must make `fetch` end non-Succeeded.
#
#   NS   the namespace the PipelineRun `run` lives in
#
#   {"fetch_reason":"GitCloneFailed"}   (or {"fetch_reason":""} if absent)
#
# The chainsaw `assert:` tree carries the checks (present, not "Succeeded").
set -euo pipefail

: "${NS:?set NS}"

reason=$(kubectl -n "$NS" get taskrun \
	-l tekton.dev/pipelineTask=fetch,tekton.dev/pipelineRun=run \
	-o jsonpath='{.items[0].status.conditions[0].reason}')

jq -nc --arg r "$reason" '{fetch_reason: $r}'
