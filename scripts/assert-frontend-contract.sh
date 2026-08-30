#!/usr/bin/env bash
# assert-frontend-contract.sh <checkout-dir> — verify a cv_frontend checkout
# matches what the pipeline assumes (docs/frontend-contract.md). Fails loud on
# the first missing path so a layout change surfaces at `resolve`, not three
# Tasks later.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/log.sh
source "$HERE/lib/log.sh"

DIR="${1:-}"
[ -n "$DIR" ] && [ -d "$DIR" ] || die "usage: assert-frontend-contract.sh <checkout-dir>"

# Keep in sync with docs/frontend-contract.md "Paths that MUST exist".
required_files=(
	server.ts
	tsconfig.json
	package.json
	package-lock.json
	app/router.ts
	app/routes.ts
	app/assets.ts
)
required_dirs=(app public)

for f in "${required_files[@]}"; do
	[ -f "$DIR/$f" ] || die "cv_frontend contract: missing file '$f' (docs/frontend-contract.md)"
done
for d in "${required_dirs[@]}"; do
	[ -d "$DIR/$d" ] || die "cv_frontend contract: missing dir '$d/' (docs/frontend-contract.md)"
done

# package.json shape the build Task depends on.
node_type="$(jq -r '.type // ""' "$DIR/package.json")"
[ "$node_type" = "module" ] || die "cv_frontend contract: package.json .type must be \"module\", got '$node_type'"

for s in start test typecheck; do
	jq -e --arg s "$s" '.scripts[$s]' "$DIR/package.json" >/dev/null \
		|| die "cv_frontend contract: package.json .scripts.$s is missing"
done

jq -e '.dependencies.remix' "$DIR/package.json" >/dev/null \
	|| die "cv_frontend contract: 'remix' is not a dependency"

log_kv step=frontend-contract result=ok dir="$DIR"
