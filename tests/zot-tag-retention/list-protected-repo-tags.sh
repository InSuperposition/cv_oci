#!/usr/bin/env bash
# list-protected-repo-tags.sh — print the tags on cv / cv-frontend / timoni.
# The live retention policy's globs must leave them untouched (they match no
# throwaway-repo pattern, so retention skips them entirely).
#
#   {"cv":["git-...",...],"cv_frontend":[...],"timoni":[...]}
#
# A chainsaw assert: tree checks: cv still has a git-<sha> tag; cv-frontend and
# timoni each have at least one tag.
set -euo pipefail

_here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/_resources/lib.sh
. "$_here/../_resources/lib.sh"
zot=$(cv_zot)

tags() {
	local out
	out=$(crane ls --insecure "${zot}/$1" 2>/dev/null || true)
	printf '%s' "$out" | jq -R . | jq -sc '[.[] | select(length > 0)]'
}

jq -nc \
	--argjson cv "$(tags cv)" \
	--argjson fe "$(tags cv-frontend)" \
	--argjson tm "$(tags timoni)" \
	'{cv:$cv, cv_frontend:$fe, timoni:$tm}'
