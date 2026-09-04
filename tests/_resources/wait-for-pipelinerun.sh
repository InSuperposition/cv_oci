#!/usr/bin/env bash
# wait-for-pipelinerun.sh <name> <namespace> — block until a PipelineRun
# succeeds; fail FAST (with the condition message) the instant it goes
# Succeeded=False.
#
# Why a script and not a chainsaw `assert:` — a pure `assert: Succeeded=True`
# polls until it matches OR the step timeout (25m) expires, so a genuine
# pipeline failure would burn the full ceiling before `catch:` runs. This keeps
# the fail-fast-with-message behaviour of the original poll loops.
#
#   DEADLINE_SECONDS   overall wait budget (default: 1400)
#
# Exit 0 on success. Exit 1 on Succeeded=False (prints the message to stderr) or
# on the deadline.
set -euo pipefail

name=${1:?usage: wait-for-pipelinerun.sh <name> <namespace>}
ns=${2:?usage: wait-for-pipelinerun.sh <name> <namespace>}
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
