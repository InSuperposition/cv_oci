#!/usr/bin/env bash
# On-failure diagnostic (chainsaw `catch:`): print the referrer tree on the
# deployed cv digest, if there is one. Never fails the run.
set -eu
_here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/reconstruction-verified/lib.sh
. "$_here/lib.sh"

ref=$(cv_deployed_ref 2>/dev/null || true)
[ -n "$ref" ] && oras discover --insecure --format tree "$ref" 2>/dev/null || true
