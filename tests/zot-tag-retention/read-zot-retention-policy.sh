#!/usr/bin/env bash
# read-zot-retention-policy.sh — guard that the live zot has loaded the Slice 7
# storage.retention policy in the exact shape this suite depends on: the 5
# throwaway-test-repo globs, deleteUntagged true, keepTags [".*"] pushedWithin
# 168h.
#
# T8a asserts in-script (verbatim from the original probe). T8b prints
# {"loaded":bool,"matches_shape":bool} and a chainsaw assert: tree takes over.
set -euo pipefail

# zot echoes the fully-resolved config as one JSON line at startup.
echo_line=$(kubectl -n cv-pipeline logs deploy/zot --tail=-1 2>/dev/null \
	| grep '"message":"configuration settings"' | tail -1)
[ -n "$echo_line" ] || { echo "no zot config echo — is zot running?" >&2; exit 1; }

pol=$(printf '%s' "$echo_line" | jq -c '.params.Storage.Retention.Policies // empty')
[ -n "$pol" ] || {
	echo "zot has NO retention policy loaded." >&2
	echo "apply manifests/zot/configmap.yaml and: kubectl -n cv-pipeline rollout restart deploy/zot" >&2
	exit 1
}

match=$(printf '%s' "$pol" | jq -c '
	map(select(
		(.Repositories | sort) == ["chainsaw-**","cv-e2e-**","cv-neg-**","cv-repro-**","dbg-**"]
		and .DeleteUntagged == true
		and .KeepTags[0].Patterns == [".*"]
		and .KeepTags[0].PushedWithin == 604800000000000
	)) | length')

[ "$match" = 1 ] || {
	echo "live retention policy does not match the Slice 7 shape:" >&2
	printf '%s\n' "$pol" | jq . >&2
	exit 1
}
