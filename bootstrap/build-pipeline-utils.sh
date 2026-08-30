#!/usr/bin/env bash
# build-pipeline-utils.sh — build the one image every cv_oci Task runs in.
#
# Uses apko (no Dockerfile, no daemon-build) to assemble a Wolfi image from the
# pinned package set in bootstrap/pipeline-utils/apko.yaml + apko.lock.json,
# then `docker load`s it into the OrbStack image store (Slice 1 has no
# registry). Prints the resulting digest.
#
# Two-phase digest flow (docs/bootstrap-toolchain.md): this prints the digest;
# a human writes it into digests.cue (`images.pipelineUtils`) and re-runs
# scripts/gen-digests.sh. `--check` compares the built digest against the one
# recorded in digests.cue and fails on drift.
#
# Pinned host tools: apko, crane, docker, cue, jq.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/log.sh
source "$ROOT/scripts/lib/log.sh"
cd "$ROOT/bootstrap/pipeline-utils"

need apko
need crane
need docker

MODE="${1:-build}"   # build | check
TAG="cv/pipeline-utils:slice1"
TAR="$(mktemp -t pipeline-utils.XXXXXX).tar"
trap 'rm -f "$TAR"' EXIT

log_kv step=pipeline-utils action=apko-build
apko build apko.yaml "$TAG" "$TAR" --sbom=false --arch arm64 --lockfile apko.lock.json >/dev/null

DIGEST="$(crane digest --tarball "$TAR")"
log_kv step=pipeline-utils digest="$DIGEST"

RECORDED=""
if command -v cue >/dev/null 2>&1; then
	RECORDED="$(cd "$ROOT" && cue export ./digests.cue --out json | jq -r '.images.pipelineUtils // ""')"
fi

if [ "$MODE" = "check" ]; then
	[ "$DIGEST" = "$RECORDED" ] || die "pipeline-utils digest drift: built $DIGEST, digests.cue has ${RECORDED:-<empty>} — rebuild, update digests.cue, gen-digests, commit together"
	log_kv step=pipeline-utils check=ok
	exit 0
fi

docker load -i "$TAR" >/dev/null
log_kv step=pipeline-utils action=docker-load loaded="${TAG}-arm64"

if [ "$DIGEST" != "$RECORDED" ]; then
	cat >&2 <<EOF

  pipeline-utils built: $DIGEST
  digests.cue records:  ${RECORDED:-<empty>}

  To pin it:
    1. set  images.pipelineUtils: "$DIGEST"  in digests.cue
    2. scripts/gen-digests.sh
    3. commit digests.cue + digests.env + params.yaml together
EOF
fi
