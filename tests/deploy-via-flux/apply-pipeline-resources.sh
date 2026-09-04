#!/usr/bin/env bash
# apply-pipeline-resources.sh — apply the Task + Pipeline into cv-pipeline.
#
# Every other suite applies these into its OWN Chainsaw-managed ephemeral
# namespace, where a bare `apply:` op already targets it. This suite runs
# against the FIXED cv-pipeline namespace — Chainsaw's `apply:` has no
# namespace-override field (that only exists on read ops like `get`), and
# setting spec.namespace.name: cv-pipeline at the test level would make
# Chainsaw treat cv-pipeline as ITS managed namespace, created and DELETED at
# test end. So this one apply stays a script.
set -euo pipefail

_here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/_resources/lib.sh
. "$_here/../_resources/lib.sh"
cd "$(cv_repo_root)"

kubectl apply -n cv-pipeline -f tasks/buildpacks.yaml -f pipeline/pipeline.yaml >/dev/null
