#!/usr/bin/env bash
# list-protected-repo-tags.sh — guard that the live retention policy's globs
# leave cv / cv-frontend / timoni untouched (they match no throwaway-repo
# pattern, so retention must skip them entirely).
#
# T8a asserts in-script. T8b prints
#   {"cv":["git-...",...],"cv_frontend":[...],"timoni":[...]}
# and a chainsaw assert: tree takes over.
set -euo pipefail

_here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/_resources/lib.sh
. "$_here/../_resources/lib.sh"
zot=$(cv_zot)

cv=$(crane ls --insecure "${zot}/cv" 2>/dev/null | tr '\n' ' ')
fe=$(crane ls --insecure "${zot}/cv-frontend" 2>/dev/null | tr '\n' ' ')
tm=$(crane ls --insecure "${zot}/timoni" 2>/dev/null | tr '\n' ' ')
echo "cv=[$cv] cv-frontend=[$fe] timoni=[$tm]"

printf '%s' "$cv" | grep -q 'git-' || { echo "FAIL: cv lost its git-<sha> tag" >&2; exit 1; }
[ -n "$(printf '%s' "$fe" | tr -d '[:space:]')" ] || { echo "FAIL: cv-frontend has no tags" >&2; exit 1; }
[ -n "$(printf '%s' "$tm" | tr -d '[:space:]')" ] || { echo "FAIL: timoni has no tags" >&2; exit 1; }
