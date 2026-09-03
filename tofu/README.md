# `tofu/` — Flux provisioning for the cv-frontend deploy loop

## Abstract

OpenTofu provisions everything the GitOps deploy path needs that `bootstrap.sh`
(frozen at the pre-Flux layer) does not: the Flux install, the seed Secrets, and
the Flux custom resources. The Tekton pipeline's `deploy` task then publishes a
signed OCI manifest artifact per verified build; Flux reconciles it.

## Goals

- Install Flux `source-controller` + `kustomize-controller` (no helm/notification).
- Copy the Chains cosign public key and zot's CA off the live cluster into
  `flux-system` (never committed).
- Create the `cv-frontend` `OCIRepository` (semver, cosign-gated, TLS-trusted)
  and `Kustomization` (prune, self-heal).
- Be idempotent: `tofu apply` on a provisioned cluster is a no-op.

## Constraints

- `bootstrap.sh` is frozen — no additions. New provisioning lives here.
- No scripting in configuration: manifests are declarative resources, not
  `local-exec` shell. The vendored `flux/components.yaml` is the only file, and
  it is upstream `flux install --export` output plus three documented pins.
- Digests: the Flux controller images are pinned in `flux/components.yaml` to the
  same values recorded in `../digests.cue` (`fluxSourceController`,
  `fluxKustomizeController`).
- Flux scope is the `cv-frontend` app only. zot / cert-manager / Chains stay
  `bootstrap.sh` `kubectl apply`.

## Prerequisites

- `bootstrap.sh` has run: `cv-pipeline` namespace, zot (TLS via cert-manager),
  Tekton Pipelines + Chains, `signing-secrets` in `tekton-chains`, `zot-tls` in
  `cv-pipeline`.
- `kubectl` context `orbstack` reachable.

## Usage

```sh
cd tofu
tofu init      # downloads alekc/kubectl + hashicorp/kubernetes providers
tofu plan
tofu apply
```

Tear down (leaves bootstrap.sh's layer intact):

```sh
tofu destroy
```

## Files

| File | Purpose |
|---|---|
| `versions.tf` | provider + OpenTofu version constraints |
| `providers.tf` | kubectl + kubernetes providers, `orbstack` context |
| `variables.tf` | namespaces, zot artifact repo, semver range, intervals |
| `flux/components.yaml` | vendored + pinned Flux manifests (re-vendor steps in its header) |
| `flux-install.tf` | applies `flux/components.yaml` |
| `secrets.tf` | `cosign-public-key` + `zot-ca` Secrets from the live cluster |
| `flux-source.tf` | `cv-frontend` OCIRepository + Kustomization |
| `outputs.tf` | flux namespace, OCIRepository ref, artifact repo |

## Not here (yet)

- **zot htpasswd auth + tag immutability** — Slice 5c-B (zot-config change,
  cluster-wide blast radius, wired separately).
- **Infra under GitOps** (cert-manager / zot / Chains reconciled by Flux) —
  deferred, see the design doc.
