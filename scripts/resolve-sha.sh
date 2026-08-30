#!/usr/bin/env bash
# resolve-sha.sh <repo-url> <ref> — resolve a git ref to a full commit SHA.
#
#   ref is a 40-hex SHA  -> passed through (existence verified after clone)
#   ref is a branch/tag   -> resolved via `git ls-remote`
#   anything else / no match -> exit 1, loud
#
# Prints the full 40-hex SHA to stdout (nothing else — the Task captures it as
# a result). All diagnostics go to stderr.
#
# Test override: CV_FRONTEND_REMOTE replaces <repo-url> (a local bare repo).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/log.sh
source "$HERE/lib/log.sh"

need git

REPO="${CV_FRONTEND_REMOTE:-${1:-}}"
REF="${2:-}"
[ -n "$REPO" ] || die "usage: resolve-sha.sh <repo-url> <ref>"
[ -n "$REF" ]  || die "usage: resolve-sha.sh <repo-url> <ref>  (ref is empty)"

if printf '%s' "$REF" | grep -Eqx '[0-9a-f]{40}'; then
	log_kv step=resolve kind=sha ref="$REF"
	printf '%s\n' "$REF"
	exit 0
fi

# Reject a short SHA explicitly rather than letting ls-remote silently miss it.
if printf '%s' "$REF" | grep -Eqx '[0-9a-f]{7,39}'; then
	die "ref '$REF' looks like a short SHA — pass the full 40-hex commit SHA"
fi

# Resolve a branch or tag. Prefer an exact tag, then a branch.
line="$(git ls-remote "$REPO" "refs/tags/$REF^{}" "refs/tags/$REF" "refs/heads/$REF" 2>/dev/null | head -1 || true)"
[ -n "$line" ] || die "ref '$REF' not found in $REPO (no matching tag or branch)"

sha="$(printf '%s' "$line" | cut -f1)"
printf '%s' "$sha" | grep -Eqx '[0-9a-f]{40}' || die "resolved value for '$REF' is not a full SHA: $sha"

log_kv step=resolve kind=ref ref="$REF" sha="$sha"
printf '%s\n' "$sha"
