# shellcheck shell=bash
# Shared logging + failure helpers. Source this; do not execute it.
#
#   source "$(dirname "$0")/lib/log.sh"
#   log_kv step=resolve app_sha="$APP_SHA"
#   die "release tree is empty"

# Structured key=value line to stderr, prefixed with an ISO-8601 UTC timestamp
# and the calling script's basename. Machine-greppable, human-readable.
log_kv() {
	local ts script
	ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	script="$(basename "${BASH_SOURCE[1]:-$0}")"
	printf '%s %s %s\n' "$ts" "$script" "$*" >&2
}

# Fail loud (Rule 13). Never swallow-and-continue.
die() {
	log_kv level=fatal msg="$*"
	exit 1
}

# Require a command on PATH or die.
need() {
	command -v "$1" >/dev/null 2>&1 || die "required tool not found: $1 (see docs/bootstrap-toolchain.md)"
}
