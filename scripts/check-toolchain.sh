#!/usr/bin/env bash
# check-toolchain.sh — report which pinned host tools are present and at what
# version. Reference: docs/bootstrap-toolchain.md.
#
# Exit 0 always (informational). Prints a table; marks MISSING / version drift.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/log.sh
source "$ROOT/scripts/lib/log.sh"

# tool | pinned version | version-probe command
rows=(
	"cue|v0.17.1|cue version | awk '/^cue version/{print \$3}'"
	"kubeconform|v0.8.0|kubeconform -v"
	"kubectl|v1.37.0|kubectl version --client -o json | jq -r .clientVersion.gitVersion"
	"tkn|0.46.0|tkn version --client 2>/dev/null | awk '/Client/{print \$NF}'"
	"shellcheck|0.11.0|shellcheck --version | awk '/version:/{print \$2}'"
	"bats|1.14.0|bats --version | awk '{print \$2}'"
	"cosign|(pin at first use)|cosign version 2>&1 | awk '/GitVersion/{print \$2}'"
	"crane|(needed for Slice 1)|crane version 2>/dev/null"
	"jq|1.8.2|jq --version | sed 's/jq-//'"
	"yq|v4.53.6|yq --version | awk '{print \$NF}'"
	"git|2.55.0|git --version | awk '{print \$3}'"
)

printf '%-14s %-22s %-14s %s\n' TOOL PINNED FOUND STATUS
printf '%-14s %-22s %-14s %s\n' ---- ------ ----- ------
for r in "${rows[@]}"; do
	IFS='|' read -r tool pinned probe <<< "$r"
	if ! command -v "$tool" >/dev/null 2>&1; then
		printf '%-14s %-22s %-14s %s\n' "$tool" "$pinned" "-" "MISSING"
		continue
	fi
	found="$(eval "$probe" 2>/dev/null | head -1 | tr -d ' ')"
	found="${found:-?}"
	status="ok"
	case "$pinned" in
		v*|[0-9]*) [ "$found" = "$pinned" ] || status="drift"; ;;
	esac
	printf '%-14s %-22s %-14s %s\n' "$tool" "$pinned" "$found" "$status"
done
