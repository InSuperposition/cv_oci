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
| `trivy` | 0.74.0 | `scripts/test/negative.sh` CVE-gate scenario (`trivy sbom` against the frozen fixture). The pipeline `scan` step runs the pinned `trivy` **image** (`digests.cue` `trivyCli`), not this host binary. | `brew install trivy` / [releases](https://github.com/aquasecurity/trivy/releases) |
| `cosign` | 3.1.3 | `bootstrap.sh` phase 5 generates the Chains signing key (`cosign generate-key-pair k8s://…`, only-if-absent); `scripts/test/e2e.sh` `cosign verify` / `verify-attestation` (Slice 4). | `brew install cosign` |
| `oras` | 1.2.3 | `scripts/test/e2e.sh` `oras discover` (Slice 4 referrers). | `brew install oras` / [releases](https://github.com/oras-project/oras/releases) |

## In-cluster CRD schemas for `scripts/validate.sh`

Tekton and other CRD schemas are vendored under `schemas/` (not fetched at
validate time — offline, reproducible). Source + version recorded here as they
are added:

| Schema | Source | Version |
|---|---|---|
| Tekton `v1` (Task, Pipeline, PipelineRun, TaskRun) | https://github.com/datreeio/CRDs-catalog `tekton.dev/` | added for the pipeline |
| cert-manager `v1` (Certificate, Issuer, ClusterIssuer, CertificateRequest) | datreeio CRDs-catalog `cert-manager.io/` (`schemas/cert-manager.io/SOURCE`) | for cert-manager v1.21.1 (Slice 4 zot TLS) |
| Tekton Triggers | datreeio CRDs-catalog `triggers.tekton.dev/` | _added in the trigger slice_ |

## Vendored in-cluster components (`bootstrap.sh`, checksum-pinned)

| Component | Version | File | SHA-256 |
|---|---|---|---|
| Tekton Pipelines | v1.15.1 | `vendor/tekton/pipeline-v1.15.1.yaml` | `68da92cc…3c86` |
| cert-manager | v1.21.1 | `vendor/cert-manager/cert-manager-v1.21.1.yaml` | `5f6a499b…e408` |
| Tekton Chains | v0.29.0 | `vendor/tekton-chains/chains-v0.29.0.yaml` | `97d68bb6…aef2` |
