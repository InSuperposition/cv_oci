#!/usr/bin/env bash
# validate.sh — offline-first Kubernetes / Tekton YAML validation.
#
# There is no `tkn lint`. This runs kubeconform against:
#   1. locally vendored CRD schemas under schemas/   (Tekton lands in Slice 1)
#   2. a pinned upstream Kubernetes schema set        (K8S_SCHEMA_VER below)
#
# Also greps for hard-coded image tags/digests outside digests.cue.
#
#   validate.sh [-v] [file ...]
#
# With no file args, validates every tracked *.yaml/*.yml outside schemas/ and
# scripts/test/fixtures/. Exit 0 when everything validates (or there is nothing
# to validate yet — Slice 0). Non-zero on any invalid file or a stray hard-coded
# image reference.
#
# Pinned tool: kubeconform (see docs/bootstrap-toolchain.md).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/log.sh
source "$ROOT/scripts/lib/log.sh"
cd "$ROOT"

need kubeconform

VERBOSE=0
if [ "${1:-}" = "-v" ]; then VERBOSE=1; shift; fi

# Pin the upstream Kubernetes JSON-schema set. Bump = a reviewed commit (Rule 12).
K8S_SCHEMA_VER="v1.31.0"
K8S_LOC="https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/${K8S_SCHEMA_VER}-standalone-strict/{{ .ResourceKind }}{{ .KindSuffix }}.json"
LOCAL_LOC="schemas/{{ .Group }}/{{ .ResourceKind }}_{{ .ResourceAPIVersion }}.json"

if [ "$#" -gt 0 ]; then
	files=("$@")
else
	# Our own tracked manifests only. Excludes: vendored schemas + upstream
	# manifests, negative-test fixtures and generated
	# non-manifest YAML.
	mapfile -t files < <(
		git ls-files -- '*.yaml' '*.yml' \
		| grep -Ev '^(schemas/|vendor/|scripts/test/fixtures/|params\.yaml$)' || true
	)
fi

if [ "${#files[@]}" -eq 0 ]; then
	log_kv step=validate result=ok manifests=0 note="no YAML to validate yet"
	exit 0
fi

args=(-strict -summary -schema-location "$LOCAL_LOC" -schema-location "$K8S_LOC")
[ "$VERBOSE" -eq 1 ] && args+=(-verbose)

rc=0
kubeconform "${args[@]}" "${files[@]}" || rc=$?

# Stray image references: an `image:` line pointing at a tag or inline digest
# instead of a param/var. digests.cue + params.yaml are the only place for those.
if grep -RInE '^[[:space:]]*image:[[:space:]]*[^$#"]*[:@]' -- "${files[@]}" 2>/dev/null \
	| grep -vE '\$\(params\.|\$\{[A-Z_]+\}'; then
	log_kv level=error step=validate msg="hard-coded image reference — use a param fed from digests.cue"
	rc=1
fi

[ "$rc" -eq 0 ] && log_kv step=validate result=ok manifests="${#files[@]}"
exit "$rc"
