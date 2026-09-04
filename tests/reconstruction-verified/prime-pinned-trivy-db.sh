#!/usr/bin/env bash
# Downloads the digest-pinned Trivy vuln-DB into the run-fixed cache
# (CV_RECON_TRIVY_CACHE) once, so derive-sbom-component-sets.sh and
# derive-cve-verdict.sh can scan with --skip-db-update. No output.
set -euo pipefail
_here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/reconstruction-verified/lib.sh
. "$_here/lib.sh"
cd "$(cv_repo_root)"
# shellcheck source=/dev/null
. ./digests.env

trivy image --quiet --cache-dir "$CV_RECON_TRIVY_CACHE" --download-db-only \
  --db-repository "ghcr.io/aquasecurity/trivy-db@${TRIVYDB}"
