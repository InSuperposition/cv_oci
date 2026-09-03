# Bootstrap toolchain

The host CLIs `bootstrap/bootstrap.sh`, the digest tooling, and the acceptance
tests need. Pin these; a version bump is a reviewed commit (Rule 12).

## Pinned host tools

| Tool | Pinned version | Used for | Install |
|---|---|---|---|
| `cue` | v0.17.1 | `digests.cue` schema + `cue export` to `digests.env` / `params.yaml`; the CUE compiler behind `timoni build` (must match `modules/*/cue.mod/module.cue` `language.version`) | `brew install cue` / [releases](https://github.com/cue-lang/cue/releases) |
| `timoni` | 0.33.0 | `timoni build` of `modules/web-app/` (Slice 5b `deploy`/`smoke` render, Slice 6 `reconstruct.sh`). Build output is byte-deterministic given `(module, values, timoni+cue versions)` — P13. A bump is a reviewed commit; re-run the P13 determinism check **and rebuild the render image** (`vendor/render/README.md`). The pipeline runs `timoni` from the vendored `zot/timoni` render image (`digests.cue` `timoniImage`), not this host binary — this one is for `reconstruct.sh` and local module work. `timoni_0.33.0_linux_arm64.tar.gz` sha256 `79fe26b750084f069540941990eb2eae7eb20ec5640ed92b2029002fda41be24`. | `brew install stefanprodan/tap/timoni` / [releases](https://github.com/stefanprodan/timoni/releases) |
| `kubeconform` | v0.8.0 | offline Tekton/K8s YAML validation (`scripts/validate.sh`) | `brew install kubeconform` / [releases](https://github.com/yannh/kubeconform/releases) |
| `kubectl` | v1.37.0 (client) | apply, `rollout status` | matches the OrbStack cluster minor |
| `chainsaw` | 0.2.15 | the acceptance suite under `tests/` (`chainsaw test --config tests/.chainsaw.yaml tests/` — the config is not auto-discovered; without it the exec timeout defaults to 5s and every pipeline-wait step is SIGKILLed). **Kyverno Chainsaw** — a declarative K8s e2e tool; NOT the WithSecureLabs forensics tool of the same name that `brew install chainsaw` installs. | `brew install kyverno/chainsaw/chainsaw` / `go install github.com/kyverno/chainsaw@v0.2.15` |
| `tkn` | 0.46.0 | `tkn pipelinerun logs` in the acceptance suite's `catch` blocks | `brew install tektoncd-cli` |
| `crane` | 0.22.0 | `crane digest` / `crane config` / `crane mutate` when pinning images and in the acceptance suite (image-in-zot, tamper, repro layer hashes) | `brew install crane` |
| `shellcheck` | 0.11.0 | pre-commit lint of `scripts/` | `brew install shellcheck` |
| `bats` | 1.14.0 | `scripts/test/*.bats` (unit: `cue vet`, gen-digests idempotence, validate fixtures, the awk parser guard) — a research task tracks replacing these after OpenTofu lands (TODOS.md) | `brew install bats-core` |
| `jq` | 1.8.2 | JSONL task artifacts, the acceptance suite | `brew install jq` |
| `git` | 2.55.0 | everything | system |
| `trivy` | 0.74.0 | the `tests/cve-gate-blocks-fixable-critical` acceptance test (`trivy sbom` against the frozen fixture). The pipeline `scan` step runs the pinned `trivy` **image** (`digests.cue` `trivyCli`), not this host binary. | `brew install trivy` / [releases](https://github.com/aquasecurity/trivy/releases) |
| `cosign` | 3.1.3 | `bootstrap.sh` phase 5 generates the Chains signing key (`cosign generate-key-pair k8s://…`, only-if-absent); `tests/pipeline-acceptance` `cosign verify` / `verify-attestation` (Slice 4). | `brew install cosign` |
| `oras` | 1.2.3 | `tests/pipeline-acceptance` `oras discover` (Slice 4 referrers + the Slice 5c manifest-artifact signature). | `brew install oras` / [releases](https://github.com/oras-project/oras/releases) |
| `tofu` | v1.12.6 | `tofu/` — provisions Flux + the seed Secrets + the `cv-frontend` Flux CRs (Slice 5c). `bootstrap.sh` stays frozen at the pre-Flux layer. `tofu init` downloads `alekc/kubectl` + `hashicorp/kubernetes`; the lock file is committed. | `brew install opentofu` / [releases](https://github.com/opentofu/opentofu/releases) |
| `flux` | v2.9.4 (CLI) | re-vendoring `tofu/flux/components.yaml` (`flux install --export`). The pipeline `deploy` task runs `flux push artifact` from the pinned `ghcr.io/fluxcd/flux-cli` **image** (`digests.cue` `fluxCli`), not this host binary. | `brew install fluxcd/tap/flux` / [releases](https://github.com/fluxcd/flux2/releases) |

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
| Flux (source + kustomize controllers) | v2.9.4 | `tofu/flux/components.yaml` (`flux install --export`, then digest-pinned; applied by `tofu/`, not `bootstrap.sh`) | controller images pinned in `digests.cue` (`fluxSourceController` / `fluxKustomizeController`) |
