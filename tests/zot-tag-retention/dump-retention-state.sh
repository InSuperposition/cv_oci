#!/usr/bin/env bash
# dump-retention-state.sh — on-failure diagnostic (chainsaw `catch:`): the
# live zot's retention-module logs and any leftover retention-probe container.
# Never fails the run.
set -euo pipefail

kubectl -n cv-pipeline logs deploy/zot --tail=40 2>/dev/null | grep -i retention || true
docker ps -a --filter 'name=zot-retention-probe' 2>/dev/null || true
