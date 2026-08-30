# Bootstrap toolchain

The host CLIs `scripts/bootstrap.sh` and the Slice 0 tooling need **before**
anything exists in-cluster. Pin these; a version bump is a reviewed commit
(Rule 12).

## Pinned host tools

| Tool | Pinned version | Used for | Install |
|---|---|---|---|
| `cue` | v0.17.1 | `digests.cue` schema + `cue export` to `digests.env` / `params.yaml` | `brew install cue` / [releases](https://github.com/cue-lang/cue/releases) |
| `kubeconform` | v0.8.0 | offline Tekton/K8s YAML validation (`scripts/validate.sh`) | `brew install kubeconform` / [releases](https://github.com/yannh/kubeconform/releases) |
| `kubectl` | v1.37.0 (client) | apply, `rollout status`, `--dry-run=server` (Slice 1+) | matches the OrbStack cluster minor |
| `tkn` | 0.46.0 | `tkn pipeline start`, `tkn pipelinerun logs` | `brew install tektoncd-cli` |
| `shellcheck` | 0.11.0 | pre-commit lint of `scripts/` | `brew install shellcheck` |
| `bats` | 1.14.0 | `scripts/test/` unit tests | `brew install bats-core` |
| `cosign` | (present — pin at first use) | verify Distroless base signature (Slice 1); `cosign verify` (Slice 4) | `brew install cosign` |
| `crane` | **not yet installed** — needed for Slice 1 | OCI assembly, `pipeline-utils` build, `crane digest` | `brew install crane` / [go-containerregistry releases](https://github.com/google/go-containerregistry/releases) |
| `jq` | 1.8.2 | JSONL task artifacts, scripting | `brew install jq` |
| `yq` | v4.53.6 | YAML scripting | `brew install yq` |
| `git` | 2.55.0 | everything | system |
| `openssl` | system libressl/openssl | the zot CA + server cert (Slice 1) | system |

Regenerate this table's "present" column: `scripts/check-toolchain.sh` (Slice 0.2).

## Two-phase `pipeline-utils` digest flow (Slice 1)

`pipeline-utils` is a pinned OCI image whose digest lives in `digests.cue`. But
the pipeline can't build its own tooling image, and the digest is both an input
(referenced by every Task) and an output (of the build). Flow:

1. **Phase 0** — `bootstrap.sh` builds `pipeline-utils` out-of-cluster with the
   host `crane` from a pinned base + the pinned tool binaries + `scripts/`, then
   `docker load`s it into the OrbStack image store (no registry in Slice 1;
   `crane push` to zot from Slice 3), and captures the resulting digest.
2. **Phase 1** — write that digest into `digests.cue`
   (`pipelineUtils: "sha256:..."`), run `scripts/gen-digests.sh`, commit.
3. **CI drift check** — recompute a content hash of the image inputs (base
   digest + tool versions + `scripts/` tree hash). If it changes and
   `digests.cue`'s `pipelineUtils` was not updated in the same commit, fail.

Contents (Slice 1): `bash`, `git`, `crane`, `cue`, the `docker` CLI, and
`scripts/` at `/opt/cv/scripts/`. `trivy` is added at Slice 3, `cosign` at
Slice 4.

## In-cluster CRD schemas for `scripts/validate.sh`

Tekton and other CRD schemas are vendored under `schemas/` (not fetched at
validate time — offline, reproducible). Source + version recorded here as they
are added:

| Schema | Source | Version |
|---|---|---|
| Tekton `v1` (Task, Pipeline, PipelineRun, TaskRun) | https://github.com/datreeio/CRDs-catalog `tekton.dev/` | _added in Slice 1_ |
| Tekton Triggers | datreeio CRDs-catalog `triggers.tekton.dev/` | _added in Slice 4_ |
