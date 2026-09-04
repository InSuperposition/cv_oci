#!/usr/bin/env bash
# wait-for-pipelinerun.sh — block until a PipelineRun succeeds; fail FAST (with
# the condition message) the instant it goes Succeeded=False.
#
# Why a script and not a chainsaw `assert:` — a pure `assert: Succeeded=True`
# polls until it matches OR the step timeout (25m) expires, so a genuine
# pipeline failure would burn the full ceiling before `catch:` runs. This keeps
# the fail-fast-with-message behaviour of the original poll loops.
#
#   NAME / $1          PipelineRun name  (chainsaw templates `env` values, not
#   NS   / $2          namespace          `args` — call sites pass these as env)
#   DEADLINE_SECONDS   overall wait budget (default: 1400)
#
# Exit 0 on success. Exit 1 on Succeeded=False (prints the message to stderr) or
# on the deadline.
set -euo pipefail

name=${NAME:-${1:?set NAME (or pass name as $1)}}
ns=${NS:-${2:?set NS (or pass namespace as $2)}}
deadline=$(( $(date +%s) + ${DEADLINE_SECONDS:-1400} ))

while :; do
	status=$(kubectl -n "$ns" get pipelinerun "$name" \
		-o jsonpath='{.status.conditions[0].status}' 2>/dev/null || true)
	case "$status" in
		True)
			jq -nc --arg n "$name" --arg ns "$ns" '{name: $n, namespace: $ns, succeeded: true}'
			exit 0
			;;
		False)
			kubectl -n "$ns" get pipelinerun "$name" \
				-o jsonpath='{.status.conditions[0].message}' >&2
			echo >&2
			exit 1
			;;
	esac
	if [ "$(date +%s)" -ge "$deadline" ]; then
		echo "pipelinerun ${ns}/${name} did not finish within the deadline (status=${status:-<none>})" >&2
		exit 1
	fi
	sleep 10
done
