# cv_oci — Multi-Architecture Tekton Supply-Chain Pipeline

Status: ACTIVE (sole source of truth)
Supersedes: the `plan/` directory (deleted 2026-08-30) and the /office-hours
draft of 2026-08-29.
Review record (the "why" behind every decision here):
`docs/designs/pipeline-restructure-review-2026-08-30.md` (CEO review + eng review
+ two Codex passes).

## Abstract

A learning + portfolio pipeline that builds a Node app into a signed,
provenance-bearing OCI image with no Docker daemon and no Dockerfile. The git
history *is* the deliverable: each commit demonstrates exactly one subsystem and
checks out clean. Work is ordered into vertical slices — a running single-arch
signed release end-to-end before any breadth (multi-arch, promotion, GitOps).

## Goals

- Learn the supply-chain stack hands-on: Tekton, `crane`, distroless, zot, Trivy,
  Tekton Chains, cosign, Timoni, Flux.
- One bisect-safe commit per subsystem. `git bisect` the supply chain itself.
- Every artifact identified by content digest, never by a mutable tag.
- A portfolio artifact: the commit history reads as a coherent story.

## Constraints

- **Learning + portfolio** (`cv_` prefix, public repo). Optimize for "each commit
  demonstrates one subsystem," not delivery speed.
- **Local dev:** OrbStack Kubernetes on Apple Silicon. **arm64 nodes only** until
  the Slice 5 entry gate.
- **Portable to any conformant Kubernetes** — no OrbStack host dependency in the
  pipeline. *Asterisk:* registry-trust bootstrap (getting the kubelet / container
  runtime to trust the in-cluster zot cert) is per-platform node configuration.
  Kubernetes treats registry trust as node/runtime config; that step is
  documented per platform, not made portable.
- **App source is a separate repo:** `github.com/InSuperposition/cv_frontend`
  (`../frontend`), `remix@3.0.0-beta.10`, Node `>=24.3.0`. The pipeline builds it
  by pinned commit SHA.
- **No Docker daemon, no Dockerfile, no QEMU/binfmt** (see Rule 3), **no private
  Fulcio or Rekor**, **no rebuild-based promotion**, **no mutable release
  identity**.

## What makes this worth building

A commit-addressable release graph with no Docker daemon anywhere:

```
 git sha -> normalized filesystem tree -> crane append onto distroless
         -> content digest -> signed -> SLSA provenance
         -> config packaged as a signed OCI module -> reconciled by digest
```

---

## Key facts established during review (do not re-derive)

- **`remix@3.0.0-beta.10` has no `build` command.** CLI verbs: `completion`,
  `new`, `db`, `doctor`, `routes`, `test`, `version`. `remix/assets`
  `createAssetServer` compiles browser assets on demand via esbuild at request
  time (`minify: !isDevelopment`, `watch: isDevelopment`). There is no
  ahead-of-time asset-emit API. The framework's own deployment model keeps the
  asset server running in production with `watch: false` + `fingerprint`.
- **Two repos, so "one git commit = release identity" was never true here.**
  Release identity is the child/index digest; provenance binds the `cv_frontend`
  SHA + the `cv_oci` pipeline-definition identity + every pinned tool/base digest.
- **Tekton Chains signs *after* a PipelineRun completes**, observe-only. Nothing
  in the signing run can consume its own signature, and a Chains failure does not
  fail that run. Verification and deploy must be a *separate* PipelineRun.
- **Tekton Triggers is HTTP-only** and Tekton emits events on PipelineRun
  condition transitions, not on later metadata/annotation changes. You cannot
  trigger off `chains.tekton.dev/signed=true`.
- **`tkn` has no `lint` subcommand.** Offline Tekton YAML validation = kubeconform
  against pinned CRD schemas. `kubectl apply --dry-run=server` needs the CRDs
  installed (Slice 1+).
- **Remote-resolving/pinning a Pipeline does not pin its referenced Tasks** —
  cluster-local `taskRef.name` stays mutable. Every Task is inlined or
  independently git-resolved by commit.
- **`gcr.io/distroless/nodejs24-debian12:nonroot`** exists, is multi-arch
  (amd64/arm64/s390x/ppc64le), cosign-signed keyless (GitHub Actions workflow
  identity). Entrypoint `node`. Node 24 matches the app's `engines`.
- **zot** does CVE scanning (embedded Trivy) + storage. It does **not** author
  SBOMs — Trivy authors, zot stores.

---

## Approach: vertical slices

Chosen over "keep the old phase order, swap tools" (which stalls at multi-arch
with no amd64 node) and over "two docs to keep in sync" (the aspirational half
rots). One doc, invariants marked active vs deferred.

Effort: M, spread over ~30 commits. Risk: low — each slice is an independently
valid, demoable system (Gall's Law); the risky infra (2nd arch node) comes after
the rest is understood.

Cost acknowledged: "release identity = multi-arch index digest" is not true until
Slice 5. Early releases are single-manifest. This doc says so.

### Slice list

| Slice | Delivers | Entry gate |
|-------|----------|------------|
| 0 | Plan is internally consistent; config + validation tooling | — |
| 1 | Running arm64 release, deployed by digest (tracer bullet) | "The Assignment" done; `/healthz` in `cv_frontend` |
| 1.5 | Per-stage least-privilege ServiceAccounts | Slice 1 green |
| 2 | Determinism + reproducibility; Option C asset snapshot; repro CronJob | Slice 1 green |
| 3 | CVE gate ("as of now") + SBOM | Slice 2 green |
| 4 | Tekton Chains: build run + separate verify+deploy run; K8s cosign key | Slice 3 green |
| 5 | amd64 + Matrix + multi-arch index | **amd64 node decided and joined** |
| 6 | Promotion + immutability + zot authz | Slice 5 green |
| 7 | GitOps handoff: Timoni app module + Flux | Slice 6 green |
| OpenBao | Persistent OpenBao, transit signing, migrate cosign to KMS URI | Slice 7 green |

---

## Slice 0 — Baseline (docs + tooling, no pipeline behavior)

### 0.1 — Plan baseline

- This document rewritten as sole source of truth; `plan/` deleted, its reference
  content migrated below (glossary, operational rules, security model, test
  layers).
- `CLAUDE.md`, `TODOS.md`, `docs/debt.md`, `docs/runbook.md`,
  `docs/bootstrap-toolchain.md`, `.gitignore` committed.
- **Acceptance:** no behavior changes. This doc does not *prescribe* `remix
  build`, a distributed FS as the artifact bus, `artifacts.pipelinerun.format` of
  `slsa/v2`, or `tkn lint` (all four are called out here as non-options). The
  slice list is internally consistent — every "Slice N green" gate refers to a
  slice defined above it.

### 0.2 — Config + validation tooling

- `digests.cue` — the single source of truth for every pinned image digest. A CUE
  schema constrains each value to `=~"^sha256:[0-9a-f]{64}$"`. Values are filled
  in as components land in later slices (two-phase for `pipeline-utils`, see
  `docs/bootstrap-toolchain.md`).
- `scripts/gen-digests.sh` — `cue export` `digests.cue` to a committed
  `digests.env` (sourced by scripts, `envsubst` on manifests) and a committed
  Tekton `params.yaml` (Task/Pipeline param defaults). CUE binary version pinned.
- `scripts/validate.sh` — kubeconform over the repo's tracked `*.yaml`. CRD
  schemas: vendored locally under `schemas/` (Tekton lands in Slice 1); the
  Kubernetes core schema set is pinned by version (`v1.31.0`) via a fixed
  upstream URL rather than vendored wholesale (the full set is hundreds of files;
  a version-pinned URL is reproducible enough for a local learning repo — see
  `docs/debt.md`). Exits 0 on an empty match set (Slice 0 has no pipeline YAML
  yet), nonzero on any invalid file. Also lints for hard-coded image
  tags/digests outside `digests.cue`.
- `scripts/lib/log.sh` — `log_kv key=value ...` and `die` helpers, sourced by
  every script.
- `.githooks/pre-commit` + `git config core.hooksPath .githooks` — runs
  `shellcheck` on `scripts/`, `scripts/validate.sh`, and `bats scripts/test/`.
  Bypassable with `--no-verify`.
- `scripts/test/` — bats. Slice 0 tests: `gen-digests` produces the expected
  files; a malformed digest string in a fixture fails `cue vet`; `validate.sh`
  rejects `scripts/test/fixtures/broken-task.yaml`.
- **Acceptance:** `scripts/validate.sh` exits 0 on the current tree and nonzero on
  the broken fixture. `scripts/gen-digests.sh` is idempotent (re-run → no diff).
  The pre-commit hook blocks a commit that fails shellcheck or a bats test.
  `kubectl apply --dry-run=server` is **not** part of Slice 0 — it needs the CRDs
  from Slice 1.

---

## Slice 1 — Running arm64 release, deployed by digest (tracer bullet)

**Prerequisite ("The Assignment"):** in `../frontend`, run the app from a
prod-only `node_modules` copy (`npm ci --omit=dev` in a scratch dir) with
`NODE_ENV=production node --import remix/node-tsx server.ts`. Hit `/` and an
`/assets/*` URL. Record: exact files the runtime touches, whether esbuild runs at
request time, release-tree contents. That answer finalizes the `build` Task.

**`cv_frontend` prep (a commit in that repo, bumps the pinned SHA):** add a
`/healthz` route returning 200 `text/plain` without SSR; add a router test
(`node --import remix/node-tsx --test`) asserting `GET /healthz` → 200 and
`GET /` → 200; gate readiness on the startup asset-warm completing.

### Build step: Option A (with Option C at Slice 2)

Slice 1 ships **Option A**: the Remix asset server runs inside the runtime image
with `watch: false`, `fingerprint: { buildId: APP_SHA }`, and a warm-on-startup
step so the smoke probe and first real request hit a warm cache. The runtime
image therefore carries esbuild (via `remix/node-tsx` + the asset server). This
is an accepted, recorded compromise (`docs/debt.md`) — Remix 3's supported
deployment model requires an in-process compiler. Slice 2 evaluates **Option C**
(snapshot the browser asset graph to static files, serve via `staticFiles`, drop
request-time bundling).

### No in-cluster registry in Slice 1 (revises 2a-A / "zot in Slice 1")

OrbStack's k8s pulls images through the OrbStack Docker daemon, which cannot
resolve `*.svc.cluster.local` and requires HTTPS-or-`insecure-registries` for
every pull (verified 2026-08-30 — see `docs/runbook.md`). Standing up an
in-cluster registry with a trust path is real OrbStack-specific work that buys
the tracer bullet nothing.

Instead: `assemble` builds the image as an OCI tarball with `crane` (no daemon,
no Dockerfile) and `docker load`s it into the OrbStack image store; `deploy` runs
it **by digest** with `imagePullPolicy: Never`. OrbStack's k8s reads the host
Docker image store directly (verified). **zot and the registry-trust story move
to Slice 3**, where the CVE gate genuinely needs a running registry. The one
compromise — the `docker load` step touches `/var/run/docker.sock` — is the
daemon as an image cache, not a builder; recorded in `docs/debt.md` with the
upgrade trigger "replace with `crane push` at Slice 3".

### Task graph

```
 cv_frontend@APP_SHA                 cv_oci pipeline definition (git-resolved by commit)
        │                                        │
        └───────────────┬────────────────────────┘
                        ▼
   resolve  ── wraps catalog git-clone (git-resolved by commit)
             + verify APP_SHA is a full sha and exists in cv_frontend
             + assert the cv_frontend contract paths exist (docs/frontend-contract.md)
             + echo APP_SHA, SOURCE_DATE_EPOCH = git commit timestamp
                        ▼
   build    ── npm ci (full) → npm audit signatures → npm run typecheck → npm test
             → npm ci --omit=dev (prune) → produce release tree into the workspace
               (server.ts, tsconfig.json, app/, public/, package.json,
                package-lock.json, node_modules/ — NO *.test.*, NO hmr.ts)
             → assert-release-tree.sh (entrypoint + prod deps present; no
               typescript/@types; no *.test.*; above floor size; df preflight)
                        ▼
   [ workspace: volumeClaimTemplate — one PVC per PipelineRun, auto-GC ]
                        ▼
   assemble ── workspace read-only
             → crane append release layer onto pinned
               gcr.io/distroless/nodejs24-debian12@sha256:… (from digests.cue),
               -o /workspace/cv.tar  (a docker-loadable tarball; NO daemon)
             → set config: USER nonroot, WORKDIR /app, ENV PORT,
               entrypoint node, CMD ["--import","remix/node-tsx","server.ts"]
             → IMAGE_DIGEST = crane digest --tarball /workspace/cv.tar
             → docker load -i /workspace/cv.tar  (via /var/run/docker.sock;
               daemon as cache only — see debt.md)
                        ▼
   smoke    ── temp Deployment + ClusterIP Service (run-scoped names, unique ns)
             image cv@sha256:<IMAGE_DIGEST>, imagePullPolicy: Never
             → a curl Job hits /healthz through the Service → expect 200
             → teardown ALWAYS (trap + ttlSecondsAfterFinished + pipeline finally)
                        ▼
   deploy   ── apply Deployment  image: cv@sha256:<IMAGE_DIGEST>,
             imagePullPolicy: Never  (consume the Task result, never a tag)
             → kubectl rollout status --timeout
             → probe /healthz through the Service
             → write the current-digest pointer ConfigMap (digest + APP_SHA + PipelineRun)
```

`npm run typecheck` needs the `typescript` devDep, so the full `npm ci` runs
before the `--omit=dev` prune (see `docs/assignment-findings.md`).

### Slice 1 also delivers

- **`pipeline-utils` image:** one pinned OCI image (`bash`, `git`, `crane`,
  `cue`, `docker` CLI, plus `scripts/` baked at a known path). Built **once
  out-of-cluster by `bootstrap.sh`** with the host `crane` and `docker load`ed
  into the OrbStack store (the pipeline can't build its own tooling image —
  chicken-egg). Tasks reference it by digest. arm64-only for now (multi-arch is
  a TODO). Two-phase digest flow: build → capture digest → write into
  `digests.cue`; CI content-hashes the image inputs and fails on a stale
  recorded digest. `trivy` / `cosign` are added to this image at Slices 3 / 4.
- **`bootstrap.sh`** — ordered, `--wait`-gated, idempotent: pinned host-toolchain
  check → Tekton Pipelines CRDs (`--for=condition=Established`) → Tekton
  controllers (`--for=condition=Available`) → enable the git-resolver feature
  flag → the `cv-pipeline` namespace + RBAC + single ServiceAccount → build +
  `docker load` `pipeline-utils`. No registry, no CA, no NetworkPolicy in Slice
  1. Order documented in the runbook.
- **Single ServiceAccount** for the whole pipeline (split in Slice 1.5).
  `automountServiceAccountToken: false` on build/assemble/smoke; `deploy` needs
  the K8s API. `assemble` mounts `/var/run/docker.sock` (hostPath) for the
  `docker load` step — the only privileged mount in Slice 1, removed at Slice 3.
- **`docs/frontend-contract.md`** — every assumption the pipeline makes about
  `cv_frontend`'s layout, asserted by the `resolve` Task.
- **`scripts/`** (in `pipeline-utils`): `resolve-sha.sh`, `assert-release-tree.sh`,
  `smoke.sh`, `deploy.sh`, `bootstrap.sh`, `lib/log.sh`.
- **Tests:** bats unit tests for every script (git fixture served by a tiny
  in-cluster git-http Deployment; one labelled `@network` test for the real
  pinned SHA). Three negative pipeline tests: bad `APP_SHA`; degenerate release
  tree; `/healthz` != 200 (+ teardown runs). (The "registry unreachable" test
  returns at Slice 3.) `scripts/test/e2e.sh` — runs the real pipeline against
  live OrbStack with a pinned fixture `APP_SHA`, unique per-run namespace,
  selects resources by PipelineRun UID, captures PipelineRun YAML + Task logs +
  events before teardown, asserts: PipelineRun success; cloned HEAD ==
  `APP_SHA`; `crane digest --tarball` matches the Task result; the image is in
  the OrbStack store; Deployment + running Pod `imageID` match that digest;
  `kubectl get deploy -o yaml` shows `@sha256`, no tag; cleanup runs after a
  forced failure.
- **Rollback** (`docs/runbook.md`): `kubectl rollout undo` / `set image
  ...@<prev>` (prev from `kubectl rollout history`). The current-digest ConfigMap
  is the human-readable pointer; the durable audit trail is the signed provenance
  in zot from Slice 4.

**Acceptance:** `scripts/test/e2e.sh` passes. `cosign verify` is documented as
manual this slice (no signature yet — Slice 4).

---

## Slice 1.5 — Least-privilege ServiceAccounts

Split the single SA into `build-sa` (source read, workspace write), `assemble-sa`
(workspace read, zot push to the candidate repo), `deploy-sa` (zot read, K8s
deploy). One clean diff, behavior preserved. **Acceptance:** `build-sa` cannot
push to zot; `deploy-sa` cannot write the workspace; the pipeline still goes
green.

---

## Slice 2 — Determinism + reproducibility

- `SOURCE_DATE_EPOCH` into layer mtimes; normalize the app-layer tar (sorted
  paths, fixed uid/gid, 0644/0755, fixed mtime). This is a `scripts/` file
  (`normalize-tar.sh`) with its own bats tests — tar normalization is fiddly (pax
  headers, ordering, xattrs, sparse files).
- Release-tree SHA-256 as a Task result; `assemble` verifies it before use.
- **Option C evaluation:** snapshot the browser asset graph via
  `assetServer.getPreloads(entry)` into `public/assets/`, patch `cv_frontend`'s
  `assets.ts` + `render.tsx` to read a manifest in production, serve via
  `staticFiles`. If C's determinism holds, adopt it and update `docs/debt.md`.
- **Reproducibility test:** build the same `APP_SHA` twice → assert identical
  release-tree digest and app-layer digest. Asserts **digests only**, never scan
  results.
- **Reproducibility CronJob:** a Tekton CronJob rebuilds a fixture `APP_SHA`
  weekly and fails loudly on app-layer digest drift.

**Acceptance:** two builds of one `APP_SHA` yield byte-identical app-layer
digests, or the exact nondeterminism source is recorded.

---

## Slice 3 — zot + CVE gate + SBOM

- **In-cluster zot** (deferred from Slice 1). Deployment + Service + PVC. On
  OrbStack the pull-trust path is: zot reachable at an address the OrbStack
  Docker daemon can resolve + one `insecure-registries` entry via
  `orb config docker` (plain HTTP — a self-signed CA needs the same node edit
  and protects nothing new on a solo cluster; revisit at Slice 6 with authz).
  This is the documented per-platform node step (`docs/runbook.md`); a portable
  cluster substitutes its own registry ingress + trust config.
- `assemble` changes: `crane push` to zot instead of `docker load`; drop the
  `/var/run/docker.sock` mount. `deploy` pulls from zot by digest.
- NetworkPolicy scoping zot to the `cv-pipeline` namespace.
- Restore the "registry unreachable" negative pipeline test.
- zot config: enable Trivy scan + search extensions.
- **CVE gate** = "policy as of now": fail on a currently-*fixable* CRITICAL. No
  baseline ledger. The Trivy scanner image + DB snapshot digest are pinned per
  run so a given run is explainable even though "latest scan" is not reproducible.
  Reproducibility (Slice 2) and CVE policy are explicitly separate concerns.
- **SBOM:** `trivy image --format spdx-json` → push as an OCI referrer
  (`cosign attest --type spdxjson`). Trivy authors, zot stores.

**Acceptance:** an image with a known fixable CRITICAL fails the gate with an
explanation; the SBOM referrer is queryable by digest.

---

## Slice 4 — Tekton Chains (signing + provenance)

Two PipelineRuns, because Chains signs after completion (see key facts).

### Build run

- Install Chains, observe-only first (existing pipeline stays green).
- Config: `artifacts.pipelinerun.format=slsa/v2alpha4`,
  `artifacts.pipelinerun.storage=oci`,
  `storage.oci.encoding-format=sigstore-bundle`, local **cosign key stored as a
  Kubernetes Secret** (not OpenBao — that's its own slice). No Rekor → the verify
  policy is explicit no-tlog.
- Emit `*_ARTIFACT_INPUTS` type hints for the `cv_frontend` source and every
  pinned base/tool digest, plus `APP_IMAGE_URL` / `APP_IMAGE_DIGEST` for the
  output. The pipeline definition is git-resolved by commit so
  `status.provenance.refSource` names it.
- Chains signs the image + attaches the PipelineRun SLSA provenance as an OCI
  referrer.

### Verify + deploy run (separate)

- Linked by an EventListener that fires on the **build run's success** (label
  filtered to build runs). Not on the signed annotation — no event fires for
  that.
- The verify run: re-fetch the source PipelineRun by name + UID → poll zot for
  the `.sig` / `.att` referrers on the digest with a bounded timeout → `cosign
  verify` + `cosign verify-attestation` (this run is the trust boundary, not the
  event payload) → assert the signed SLSA predicate's `refSource` entries name
  the expected Pipeline + every Task URI/digest → deploy.
- Idempotent on a deterministic build-UID key (CloudEvents retry/reorder/dup).
- EventListener has its own NetworkPolicy + narrow RBAC.

**Acceptance:** `cosign verify` + `cosign verify-attestation` pass on the
release; an unsigned artifact fails the verify run and never deploys; the
provenance-predicate assertion passes.

---

## Slice 5 — amd64 + Matrix + multi-arch index

**Entry gate: an amd64 node has been decided on and joined the cluster.**
Options, to be resolved before starting this slice:
- k0s / k0smotron / k0rdent-managed nodes on OrbStack VMs (likely direction).
- A managed Kubernetes dual arch pool.
- Accept QEMU and drop Rule 3.

- `arch` param (arm64 default), validate allowed values. Node scheduling via
  `kubernetes.io/arch`.
- Tekton Matrix fan-out `arch=[amd64,arm64]` from one `APP_SHA`. **Per-arch PVCs**
  (a `ReadWriteOnce` PVC cannot span two nodes — "separate subdirs" does not fix
  volume topology), or each arch clones/builds/pushes straight to zot with no
  shared workspace.
- One arch failure fails the PipelineRun. Assemble both → build an OCI index with
  exactly the two accepted children.
- **Release identity changes here:** platform digest → index digest. Chains
  subject, `cosign verify`, and deploy all switch to the index digest.

**Acceptance:** `crane manifest` on the index shows exactly `linux/amd64` +
`linux/arm64`; either arch failing produces no index.

---

## Slice 6 — Promotion + immutability + zot authz

- Candidate tag `cv:git-<full-sha>-<cv_oci-defn-id>` → index digest (the tag
  carries both identities and can't collide).
- Promote by digest: `crane cp` the exact verified digest to a unique release
  version. No rebuild.
- zot authz: release aliases not overwritable by the normal CI identity. Add
  htpasswd / full auth here (deferred from Slice 1).

**Acceptance:** promoted digest == tested digest; an overwrite of a release alias
by the CI identity is denied.

---

## Slice 7 — GitOps handoff (Timoni + Flux)

Only the **app deployment** (pipeline-infra + bootstrap → Timoni are TODOs).

- The pipeline runs `timoni build` to render the app module to Kubernetes YAML,
  pushes the rendered output as a signed OCI artifact to zot by digest, then
  bumps a Flux `OCIRepository` ref (the pipeline is what updates the watched
  digest — explicit, not a mutable tag). A Flux `Kustomization` applies it; Flux
  `OCIRepository.spec.verify` (cosign) verifies.
- The `deploy` Task stops running `kubectl apply`.
- **Release identity gains a layer:** the rendered-config artifact digest is now
  the deployment identity, linked to the image-index digest. Document the
  `config digest → image-index digest` graph with signing/promotion semantics for
  both.
- Slice 6's optional policy-controller admission folds in here.
- cert-manager revisited here (Flux may want automated certs).

**Acceptance:** a `timoni`-rendered, signed module deployed by digest; a manual
`kubectl edit` on the workload is reverted by Flux; `cosign verify` gates the
reconcile.

---

## OpenBao slice (after Slice 7)

Persistent OpenBao (file/PVC storage, Shamir unseal), transit engine for signing,
migrate cosign to the KMS URI, Chains signs via the service. Its own Rule 15 exit
test. This is the "real signing-service boundary" lesson done properly, not
wedged into Slice 4 as dev-mode.

---

## Open questions

1. **amd64 node source** — deferred to the Slice 5 entry gate (above).
2. **Option C feasibility** — resolved during Slice 2 with the asset-graph
   snapshot experiment.
3. **`/` vs `/healthz` for the smoke test** — resolved: `/healthz` added in
   Slice 1 prep.

---

# Reference (migrated from `plan/`)

## Architecture invariants

1. One `cv_frontend` commit is built (both architectures once Slice 5 lands).
2. Native nodes build native artifacts (Rule 3; active at Slice 5).
3. No release is created if either architecture fails (active at Slice 5).
4. Platform manifests are immutable once accepted.
5. The multi-platform index digest is the release identity (active at Slice 5;
   before that, the single platform digest is).
6. Promotion moves references; it never rebuilds.
7. Build and runtime base images are pinned by digest (`digests.cue`).
8. Release trees are read-only after the build stage.
9. Security metadata is attached to OCI artifacts as referrers, not scattered.
10. Every stage receives only the permissions it needs (full at Slice 1.5).

## Component boundaries

- **Git** owns: source identity, build config, pinned base-image references, the
  lockfile, Tekton definitions, security-policy config. Not: generated SBOMs or
  OCI artifacts.
- **Tekton** owns orchestration only: resolve the exact commit, schedule Tasks,
  coordinate build/assemble/scan/index, produce image URL + digest results. Not a
  general artifact database.
- **Workspace (PVC via `volumeClaimTemplate`)** is the intermediate release-tree
  bus. `build` writes; `assemble` reads read-only. One PVC per PipelineRun,
  auto-GC. (The earlier draft used a distributed filesystem here; a per-run PVC
  is the standard Tekton primitive and removes a whole component — Rule 2.)
- **crane** performs narrow OCI ops: append the app layer, set config, push
  platform manifests, create/update the index. It does not compile code.
- **Distroless Node** runtime: no shell, no package manager, no npm CLI. Non-root.
  Pinned by digest. (Under Option A it *does* carry esbuild via `remix/node-tsx`
  — recorded compromise, `docs/debt.md`, removed at Slice 2 Option C.)
- **zot** is the canonical OCI registry: platform manifests, indexes, signatures,
  provenance, SBOM referrers, vulnerability data, tag aliases. Scan + storage
  only — it does not author SBOMs.
- **Tekton Chains** owns automated trust evidence: image signing, PipelineRun
  provenance, SLSA attestation, OCI referrer storage. Prefer PipelineRun-level
  provenance over per-Task.
- **Cosign** is a verification/debugging CLI, not duplicated across pipeline steps
  where Chains already signs.

## Operational rules

1. **One problem, one owner.** dependency integrity → npm; app build → Remix;
   orchestration → Tekton; intermediate artifacts → PVC workspace; OCI ops →
   crane; registry → zot; CVE + SBOM → zot/Trivy; signing + provenance → Chains;
   verification → cosign. No second tool for the same job without a measured
   limitation.
2. **Prefer deletion over abstraction.** Before a new component: can an existing
   one do it? can the requirement be removed? can the data flow be simplified?
   can a digest eliminate mutable state?
3. **Native multi-arch only.** amd64 build → amd64 node, arm64 → arm64. No QEMU /
   binfmt by default. The point is understanding real multi-arch CI.
4. **No local architecture exception in release design.** OrbStack is a dev host;
   the architecture must also work on other conformant clusters. (Registry-trust
   bootstrap is the documented per-platform exception.)
5. **Build once.** Never rebuild during promotion.
6. **Deploy by digest.** Tags aid humans; Kubernetes receives the digest.
7. **No mutable base images.** All builder/runtime images digest-pinned in
   `digests.cue`.
8. **Keep the workspace temporary.** The PVC holds pipeline artifacts; zot holds
   durable release artifacts.
9. **Minimize the runtime filesystem** to the Distroless runtime, app build
   output, production deps, static assets, required metadata.
10. **Security evidence is attached, not scattered.** OCI referrers for SBOMs,
    signatures, provenance.
11. **Separate identities.** No one omnipotent CI ServiceAccount.
12. **Security changes are normal commits** — base-image update, builder update,
    vulnerability-policy update, Chains-config update: reviewed, tested,
    bisectable.
13. **Avoid silent fallback.** These fail rather than continue: requested arch
    node unavailable; base signature invalid; release-tree hash mismatch; SBOM
    missing; security gate unavailable; Chains signing failed; provenance absent;
    promotion digest mismatch.
14. **Add enforcement only after understanding verification.** manual verify →
    pipeline verify → admission enforcement. No policy-controller before the
    manual flow is understood.
15. **Every new dependency needs an exit test.** Document: what exact problem it
    solves; which current component can't; what complexity it adds; how it would
    be removed later. Weak answers → don't add it.

## Security model highlights

- **Input verification.** Builder + runtime images pinned by digest; changing a
  digest is a reviewed commit. `npm ci` + `npm audit signatures`; the lockfile
  controls resolution. General vulnerability policy is zot/Trivy's, not npm's.
- **Workspace boundary.** build → write, assemble → read-only, others → none. The
  release tree is hashed before assembly; the assembler verifies the hash.
- **Tekton hardening** (default Task posture): `runAsNonRoot: true`,
  `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`,
  `seccompProfile: RuntimeDefault`, `readOnlyRootFilesystem` where practical,
  `automountServiceAccountToken: false` where not needed.
- **Registry permissions** separated: assembler creates candidate manifests;
  indexer creates the candidate index; Chains attaches signatures/provenance;
  deploy is read-only; normal CI cannot delete/overwrite accepted release aliases.
- **Signing.** Chains signs the release digest. The deployed identity is the
  signed digest. Dev uses a cosign key as a K8s Secret; the shared-env
  progression is workload identity / KMS (the OpenBao slice).
- **Provenance.** PipelineRun-level SLSA. Establishes: `cv_frontend` SHA, the
  git-resolved pipeline definition, arch-specific outputs, the final digest, every
  pinned input. Verified by an acceptance test, not assumed.
- **Deployment trust gap.** Pipeline signing is not protection unless consumers
  verify. Initial rule: `cosign verify` + `cosign verify-attestation` + deploy by
  digest. Admission enforcement (policy-controller) only after the manual flow is
  understood (Slice 7).
- **Negative-space.** Runtime image has no shell / compiler* / package manager /
  SCM client / build or test tooling / registry or K8s credentials. The build
  Task has no signing credentials / deploy rights / release-tag overwrite rights.
  The deploy Task has no source write / workspace write / image-build privileges.
  (*Option A carries an in-process compiler until Slice 2 — recorded.)

## Test layers

1. **Repository validation** (pre-cluster): YAML parse, kubeconform against
   pinned CRD schemas, required-param checks, no mutable release base tags,
   supported arch values only.
2. **Application tests** (`cv_frontend`): unit, integration, server startup;
   `npm ci` + `npm audit signatures`.
3. **Script unit tests** (bats): every `scripts/*` file, happy + failure + edge;
   git fixture served in-cluster.
4. **Release-tree tests**: entrypoint + build output + prod deps present;
   build-only deps absent; release-tree digest produced; size budget.
5. **Workspace boundary tests**: build writes, assemble reads, assemble cannot
   write the completed tree.
6. **OCI assembly tests**: correct Distroless platform, signature verified,
   `/app` contents, non-root user, correct entrypoint/CMD.
7. **Native runtime smoke** (per arch, from Slice 5): run the image on a matching
   node, wait ready, request `/healthz`, expect 200, stop.
8. **Multi-arch index test** (Slice 5): index contains exactly amd64 + arm64;
   child digests match accepted results.
9. **SBOM test** (Slice 3): each image has an SBOM referrer; app + runtime
   packages appear.
10. **Vulnerability policy test** (Slice 3): fixtures for no-regression, new
    fixable CRITICAL; understandable output.
11. **Signature test** (Slice 4): `cosign verify` passes; an unsigned artifact
    fails.
12. **Provenance test** (Slice 4): predicate subject matches the final digest;
    `refSource` names the expected pipeline + tasks; `cv_frontend` SHA present;
    mismatched subject fails.
13. **Promotion test** (Slice 6): candidate digest == promoted digest.
14. **Reproducibility test** (Slice 2): rebuild a fixture commit; same
    release-tree + app-layer digests. Digests only, never scan results.

Every implementation commit passes the tests relevant to behavior introduced up
to that point. Failures stop as close as possible to their source.

## Glossary

- **OCI image** — a platform-specific container image: config + filesystem layers.
- **OCI image index** — references multiple platform manifests. Its digest is the
  release identity from Slice 5 on.
- **Manifest digest** — the SHA-256 content digest of one OCI manifest.
- **Digest-pinned reference** — `registry/app@sha256:…`; identifies exact content,
  unlike a mutable tag.
- **Tekton Pipeline / Task / Matrix** — a declarative graph of Tasks; an ordered
  set of container steps in a Pod; a fan-out mechanism for parameter combinations.
- **Tekton Chains** — observes completed runs, produces signed provenance + OCI
  signatures.
- **Tekton remote resolution (git resolver)** — fetches a pinned Task/Pipeline
  definition by git commit; populates `status.provenance.refSource`.
- **SLSA provenance** — structured evidence of how an artifact was produced.
- **SBOM** — software bill of materials; SPDX JSON here; Trivy authors.
- **Referrer** — an OCI artifact associated with another OCI digest (SBOM,
  signature, provenance).
- **Distroless** — minimal runtime images without shells or package managers.
- **crane** — narrow OCI manipulation CLI.
- **zot** — OCI-native registry, the durable release store.
- **Release tree** — the built app filesystem added to the runtime image.
- **Native build** — built on a node whose CPU arch matches the target.
- **`SOURCE_DATE_EPOCH`** — deterministic build timestamp; here the git commit
  timestamp.
- **Bisect-safe** — each accepted commit is independently buildable/testable
  enough for `git bisect` to mean something.
- **Prospective commit** — the exact commit that would enter `main` after
  merge/rebase/squash; CI tests that, not a different branch tip.
- **Promotion** — assigning a release reference to an already-built, verified
  digest. Never rebuilds.
- **Workload identity** — a short-lived identity derived from the running
  workload, not a stored key.
- **Timoni** — CUE-based Kubernetes package manager; distributes modules as OCI
  artifacts.
- **Flux `OCIRepository` / `Kustomization`** — Flux fetches an OCI artifact
  (optionally cosign-verified) and applies it.

## Distribution

The deliverable is an OCI artifact set in zot (platform image / index +
signature + provenance + SBOM referrers), consumed by a Kubernetes Deployment in
the same cluster, and — from Slice 7 — a signed Timoni config module reconciled
by Flux. No external distribution. The pipeline is its own CI/CD: `tkn`-triggered
now; a Tekton Trigger on `cv_frontend` push is a TODO.
