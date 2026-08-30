#!/usr/bin/env bash
# assert-release-tree.sh <tree-dir> — gate the build output before it is handed
# to `assemble`. Fails loud (Rule 13) at the source rather than shipping a
# broken image that only fails at smoke.
#
# Checks:
#   - the runtime entrypoint + prod deps are present
#   - build-only deps (typescript, @types) are absent
#   - test files and dev-only files are absent
#   - the tree is above a floor size (catches an empty/degenerate prune)
#   - the workspace has room (df preflight) — skipped if MIN_FREE_MB unset
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/log.sh
source "$HERE/lib/log.sh"

DIR="${1:-}"
[ -n "$DIR" ] && [ -d "$DIR" ] || die "usage: assert-release-tree.sh <tree-dir>"

FLOOR_MB="${RELEASE_TREE_FLOOR_MB:-25}"

must_exist=(
	server.ts
	tsconfig.json
	package.json
	app/router.ts
	node_modules/remix
	node_modules/.bin
)
for p in "${must_exist[@]}"; do
	[ -e "$DIR/$p" ] || die "release tree: missing '$p'"
done

must_be_absent=(
	node_modules/typescript
	"node_modules/@types/node"
	hmr.ts
)
for p in "${must_be_absent[@]}"; do
	[ ! -e "$DIR/$p" ] || die "release tree: '$p' must not be in the runtime image"
done

if find "$DIR/app" -name '*.test.*' -print -quit | grep -q .; then
	die "release tree: app/ contains a *.test.* file — exclude tests from the release tree"
fi

size_mb="$(du -sm "$DIR" | cut -f1)"
[ "$size_mb" -ge "$FLOOR_MB" ] \
	|| die "release tree: ${size_mb}MB is below the ${FLOOR_MB}MB floor — a prune probably wiped node_modules"

if [ -n "${MIN_FREE_MB:-}" ]; then
	free_mb="$(df -Pm "$DIR" | awk 'NR==2 {print $4}')"
	[ "$free_mb" -ge "$MIN_FREE_MB" ] \
		|| die "workspace: ${free_mb}MB free, need ${MIN_FREE_MB}MB"
fi

log_kv step=assert-release-tree result=ok dir="$DIR" size_mb="$size_mb"
