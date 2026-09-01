# Bootstrap toolchain

The host CLIs `bootstrap/bootstrap.sh`, the digest tooling, and the acceptance
tests need. Pin these; a version bump is a reviewed commit (Rule 12).

## Pinned host tools

| Tool | Pinned version | Used for | Install |
|---|---|---|---|
| `cue` | v0.17.1 | `digests.cue` schema + `cue export` to `digests.env` / `params.yaml` | `brew install cue` / [releases](https://github.com/cue-lang/cue/releases) |
| `kubeconform` | v0.8.0 | offline Tekton/K8s YAML validation (`scripts/validate.sh`) | `brew install kubeconform` / [releases](https://github.com/yannh/kubeconform/releases) |
| `kubectl` | v1.37.0 (client) | apply, `rollout status` | matches the OrbStack cluster minor |
| `tkn` | 0.46.0 | `tkn pipelinerun logs` in the e2e tests | `brew install tektoncd-cli` |
| `crane` | 0.22.0 | `crane digest` when pinning images; the e2e "image is really in zot" check | `brew install crane` |
| `shellcheck` | 0.11.0 | pre-commit lint of `scripts/` | `brew install shellcheck` |
| `bats` | 1.14.0 | `scripts/test/*.bats` | `brew install bats-core` |
| `jq` | 1.8.2 | JSONL task artifacts, scripting | `brew install jq` |
| `git` | 2.55.0 | everything | system |
| `trivy` | 0.67.2 | `scripts/test/negative.sh` CVE-gate scenario (`trivy sbom` against the frozen fixture). The pipeline `scan` step runs the pinned `trivy` **image** (`digests.cue` `trivyCli`), not this host binary. | `brew install trivy` / [releases](https://github.com/aquasecurity/trivy/releases) |
| `cosign` | (pin at first use) | `cosign verify` / `verify-attestation` (Slice 4) | `brew install cosign` |

## In-cluster CRD schemas for `scripts/validate.sh`

Tekton and other CRD schemas are vendored under `schemas/` (not fetched at
validate time — offline, reproducible). Source + version recorded here as they
are added:

| Schema | Source | Version |
|---|---|---|
| Tekton `v1` (Task, Pipeline, PipelineRun, TaskRun) | https://github.com/datreeio/CRDs-catalog `tekton.dev/` | added for the pipeline |
| Tekton Triggers | datreeio CRDs-catalog `triggers.tekton.dev/` | _added in the trigger slice_ |
