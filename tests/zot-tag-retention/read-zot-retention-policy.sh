#!/usr/bin/env bash
# read-zot-retention-policy.sh — print the live zot's resolved
# storage.retention policy, parsed from its startup config echo.
#
#   {"loaded":bool,"matches_shape":bool}
#
# matches_shape: repositories == the 5 throwaway-test-repo globs, sorted;
# deleteUntagged == true; keepTags[0] == {patterns:[".*"], pushedWithin:168h}.
# A chainsaw assert: tree checks both are true. If loaded is false, run
# `kubectl -n cv-pipeline rollout restart deploy/zot` — the config echo only
# appears in zot's STARTUP log, which the log buffer eventually rotates past.
set -euo pipefail

echo_line=$(kubectl -n cv-pipeline logs deploy/zot --tail=-1 2>/dev/null \
	| grep '"message":"configuration settings"' | tail -1)

if [ -z "$echo_line" ]; then
	jq -nc '{loaded: false, matches_shape: false}'
	exit 0
fi

pol=$(printf '%s' "$echo_line" | jq -c '.params.Storage.Retention.Policies // empty')
if [ -z "$pol" ]; then
	jq -nc '{loaded: false, matches_shape: false}'
	exit 0
fi

match=$(printf '%s' "$pol" | jq -c '
	map(select(
		(.Repositories | sort) == ["chainsaw-**","cv-e2e-**","cv-neg-**","cv-repro-**","dbg-**"]
		and .DeleteUntagged == true
		and .KeepTags[0].Patterns == [".*"]
		and .KeepTags[0].PushedWithin == 604800000000000
	)) | length')

jq -nc --argjson m "$match" '{loaded: true, matches_shape: ($m == 1)}'
