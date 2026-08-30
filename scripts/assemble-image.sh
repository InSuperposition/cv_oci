#!/usr/bin/env bash
# assemble-image.sh <release-tree-dir> <base-ref> <image-tag>
#
# Builds the runtime image with `crane` (no Docker daemon, no Dockerfile) and
# loads it into the local image store as <image-tag>.
#
#   - pack <release-tree-dir> into a layer rooted at /app
#   - run an ephemeral in-process registry (`crane registry serve`) so
#     `crane append` / `crane mutate` work with no persistent infrastructure
#   - append onto <base-ref>; set OCI config (workdir /app, non-root user,
#     PORT, NODE_ENV, entrypoint `node`, CMD `--import remix/node-tsx server.ts`)
#   - `docker load` it and tag it <image-tag>
#
# Prints the image digest to stdout (only that). Diagnostics -> stderr.
#
# Slice 1 note: OrbStack's `docker load` records no repo digest, so `deploy`
# references the image by <image-tag> (which encodes the full APP_SHA), not by
# @sha256. The digest printed here is recorded + verified out of band; a real
# registry at Slice 3 restores digest-ref deploy (docs/debt.md).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/log.sh
source "$HERE/lib/log.sh"
need crane; need docker

# GNU tar is required for deterministic layers (--sort, --mtime, --owner).
# pipeline-utils ships it as `tar`; on a Mac dev box use `gtar` (brew gnu-tar).
TAR="tar"
command -v gtar >/dev/null 2>&1 && TAR="gtar"
"$TAR" --version 2>/dev/null | grep -qi 'GNU tar' \
	|| die "GNU tar required (Mac: brew install gnu-tar) — found: $("$TAR" --version 2>&1 | head -1)"

TREE="${1:-}"; BASE="${2:-}"; TAG="${3:-}"
[ -n "$TREE" ] && [ -d "$TREE" ] || die "usage: assemble-image.sh <release-tree-dir> <base-ref> <image-tag>"
[ -n "$BASE" ] && [ -n "$TAG" ] || die "base / tag must be non-empty"
printf '%s' "$BASE" | grep -q '@sha256:' || die "base must be pinned by digest, got '$BASE'"

PORT="${APP_PORT:-44100}"
RUNTIME_UID="${RUNTIME_UID:-65532}"       # distroless 'nonroot'
PLATFORM="${TARGET_PLATFORM:-linux/arm64}"
NODE_BIN="/nodejs/bin/node"              # distroless nodejs24 puts node here, not on PATH
REG="127.0.0.1:${ASSEMBLE_REGISTRY_PORT:-45999}"

layer="$(mktemp -t cv-layer.XXXXXX).tar"
tarball="$(mktemp -t cv-image.XXXXXX).tar"
crane registry serve --address "$REG" >/dev/null 2>&1 &
reg_pid=$!
cleanup() {
	kill "$reg_pid" 2>/dev/null || true
	rm -f "$layer" "$tarball"
	docker rmi "${REG}/cv:built" >/dev/null 2>&1 || true
}
trap cleanup EXIT
for _ in $(seq 1 20); do crane catalog "$REG" --insecure >/dev/null 2>&1 && break; sleep 0.25; done

tar_args=(--numeric-owner --owner=0 --group=0 --sort=name)
[ -n "${SOURCE_DATE_EPOCH:-}" ] && tar_args+=(--mtime="@${SOURCE_DATE_EPOCH}")
log_kv step=assemble action=pack-layer tree="$TREE"
"$TAR" "${tar_args[@]}" -C "$(dirname "$TREE")" -cf "$layer" "$(basename "$TREE")"

log_kv step=assemble action=append base="$BASE" platform="$PLATFORM"
crane append --platform "$PLATFORM" --base "$BASE" --new_layer "$layer" -t "${REG}/cv:staged" --insecure >&2

log_kv step=assemble action=config
crane mutate --platform "$PLATFORM" "${REG}/cv:staged" --insecure -t "${REG}/cv:built" \
	-w /app -u "$RUNTIME_UID" \
	-e "PORT=${PORT}" -e "NODE_ENV=production" \
	--entrypoint "$NODE_BIN" --cmd --import --cmd remix/node-tsx --cmd server.ts >&2

crane pull --platform "$PLATFORM" --format tarball --insecure "${REG}/cv:built" "$tarball" >&2
digest="$(crane digest --tarball "$tarball")"
printf '%s' "$digest" | grep -Eqx 'sha256:[0-9a-f]{64}' || die "assemble: bad digest '$digest'"

log_kv step=assemble action=docker-load tag="$TAG"
docker load -i "$tarball" >&2
docker tag "${REG}/cv:built" "$TAG"

log_kv step=assemble result=ok digest="$digest" tag="$TAG"
printf '%s\n' "$digest"
