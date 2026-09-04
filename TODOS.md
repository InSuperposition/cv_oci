# TODOS

Deferred work. Distinct from `docs/debt.md` (accepted compromises with upgrade
triggers) — this is new work not yet scheduled into a slice.

## P2

### Planning session — declarative-first + extract all inline shell from config
- **What:** a `/plan-eng-review`-gated planning session covering the whole
  repo's scripts and test-embedded shell. Two goals:
  1. **No shell inside config YAML** (a hard rule as of 2026-09-04). Extract
     every inline `script:` in `tests/*/chainsaw-test.yaml`
     (`pipeline-acceptance`, `deploy-via-flux`, `zot-tag-retention`,
     `pipeline-rejects-*`, `pipeline-rbac-templating`, `cve-gate-*`,
     `build-is-reproducible`) into named `.sh` files — IDE syntax highlighting,
     `shellcheck -x`, and `bats` coverage all need real files. Chainsaw calls
     them via `command: { entrypoint: ./<name>.sh }`; comparisons stay in
     `assert:` (kyverno-json) trees. `tests/reconstruction-verified/` is the
     reference shape (lib.sh + one script per data-gathering job).
  2. **Every script functional, composable, reusable, conceptually isolated,
     easily tested** — one job per file, shared helpers in a `lib.sh`, no
     hidden coupling, pure where possible, a `bats` case per script.
- **Declarative-first (do this BEFORE writing shell):** for each extracted
  block, check whether a tool — **in the stack or not** — does it
  declaratively. Where an out-of-stack tool fits, the planning session
  presents it as an option with tradeoffs; **the user decides whether it
  enters the stack.** Known candidates to weigh: Flux `OCIRepository` for
  fetch+cosign-verify (already in stack); `crane`/`oras` config files;
  `cue`/`timoni` for anything YAML-shaped; a policy engine for JSON assertions
  (`conftest`/OPA, kyverno CEL `ValidatingPolicy`) vs Chainsaw's embedded
  kyverno-json.
- **Why:** the Slice 5a "retire the bash harness for Chainsaw" mandate moved
  orchestration into YAML but carried the shell along inside `script:` blocks.
  This finishes the job — declarative config, testable code.
- **Context:** Slice 6 PR #4 established the pattern
  (`tests/reconstruction-verified/`, decision `04249b46`). `bats` is currently
  only wired for `scripts/test/*.bats`; the pre-commit shellcheck glob was
  widened to `tests/**/*.sh` in the same PR.
- **Effort:** L (human, ~1–2 days) / M (CC). Its own branch, not folded into a
  feature slice.
- **Depends on:** nothing; every existing suite is green, so this is a
  behaviour-preserving refactor.

### Tighten or retire `cv-deploy-role`
- **What:** the `deploy` task no longer `kubectl apply`s (5c-A — Flux
  reconciles). `cv-deploy-role` still grants Deployment/Service write from the
  pre-Flux path. Either drop it to nothing (the task uses no cluster API) or
  fold `cv-deploy-sa` into `cv-build-sa`.
- **Why:** minimal viable surface area — an unused write grant is negative
  space with a cost.
- **Context:** Slice 5c-A. Left in place this pass to keep the diff scoped;
  the `deploy` TaskRun still runs as `cv-deploy-sa`.
- **Effort:** S. **Depends on:** 5c-A shipped + `deploy-via-flux` green.

### Registry auth (`cv_openbao` arc)
- **What:** zot `accessControl` htpasswd (anonymous pull denied) +
  `dockerconfigjson` pull Secrets wired into every consumer (pipeline
  build/scan/deploy steps, kubelet node config, Flux source-controller).
- **Why:** real registry auth is a supply-chain skill worth showing.
- **Context:** was the zot-auth half of the Slice 5c split (2026-09-03).
  Reduced to auth only —
  retention shipped in Slice 7; tag immutability is its own TODO below. The
  ~8 credential-wiring points all change when htpasswd lands regardless, so
  this fails the same solo-single-node test that parked the zot `NetworkPolicy`
  (`docs/debt.md`) and folds into the `cv_openbao` arc (OpenBao PKI as the zot
  issuer, credentials from transit/kv).
- **Effort:** M. **Depends on:** `cv_openbao` repo.

### Kyverno as a portfolio demo policy
- **What:** a single small Kyverno policy as portfolio evidence of
  admission-control knowledge — either one `validate` (e.g. `disallow-latest` /
  require-digest on the `cv` Deployment) or a `generate` policy matched *only*
  to ephemeral test namespaces. Vendored + digest-pinned like `cert-manager` /
  `tekton-chains`.
- **Why:** the original goal behind the (now superseded) decision `7e6275c3`
  "Kyverno = core plane". Admission control is a real supply-chain skill worth
  showing.
- **Context:** eng review 2026-09-02 (`04eb7e62` supersedes `7e6275c3`). The
  full "Kyverno owns per-namespace RBAC" slice was dropped: the digest policy
  fires on nothing (deploy/smoke already build `@sha256` refs; 5c makes it
  redundant), single-source generate moves `cv-pipeline`'s pipeline identity
  behind an async background reconciler on a no-redundancy node,
  `generateExisting` can't cleanly migrate live RBAC, and `bootstrap.sh` (frozen)
  has no home for the install until `tofu/` lands in 5c. If Kyverno returns it
  must be scoped so **production RBAC stays static YAML** — Kyverno never owns
  `cv-pipeline`'s identity. Its own slice, its own rule-15 exit test.
- **Rides with:** "zot tag immutability (`http.accessControl`)" — the user
  gated that item on this slice (2026-09-03), because Kyverno gives a way to
  say "the pipeline SA may create but not overwrite a tag" as policy rather
  than a blunt anonymous registry ACL.
- **Effort:** M (vendored install + 1 policy + a Chainsaw test).
- **Depends on:** P11a run (cosign-verify viability probe, Slice 5b); Slice 5c
  shipped (`tofu/` provisioning path for the install).

### cv_packs — the decoupled buildpack suite
- **What:** design doc + first commits for `github.com/InSuperposition/cv_packs`
  (empty repo, created 2026-09-01; local scaffold `../packs/`). A hand-authored,
  capability-oriented Node/npm buildpack suite (`cv/node-engine`,
  `cv/npm-install`, `cv/npm-build`, `cv/npm-start`, composite `cv/node-npm-app`),
  built as a conformance lab that diffs against the stock Paketo lane.
- **Why:** the office-hours "goal 2" (learn CNB buildpack authoring). Pulled out
  of cv_oci in the 2026-09-01 eng review because coupling it to cv_oci's
  `BUILDER_IMAGE` repeated the over-engineering the pivot cures and tied cv_oci's
  bisect-safety to an ephemeral single-node zot.
- **Context:** `docs/designs/buildpacks-pivot.md` → Deferred. Collapse the 7
  scaffold dirs (they collide with CNB reserved terms) to
  `buildpacks/ composites/ builders/ fixtures/ docs/ artifacts/`. Directory name
  == buildpack id. **Lead with `cv/npm-build`** — the one buildpack with real
  resolution logic; the other three are trivial. `cv_frontend` is one fixture;
  add a plain-TS fixture (has a build script) for `npm-build`.
- **Effort:** L (human) / M (CC), spread over many commits.
- **Depends on:** the cv_oci CNB curriculum being further along; never blocks it.

### Reproducibility CronJob
- **What:** a Tekton `CronJob` (or scheduled PipelineRun) that reruns the
  `tests/build-is-reproducible` two-build comparison weekly against the pinned
  fixture SHA and fails loudly on app-layer / SBOM-layer content-hash drift.
- **Why:** the test proves reproducibility at a point in time; the CronJob
  catches a regression from a builder/lifecycle bump between slices.
- **Context:** Slice 2 (`docs/designs/buildpacks-pivot.md`). The executable
  test landed; the CronJob is deferred for the same reason as the portability
  kind-CI below — it needs a persistent always-on cluster to be worth the
  cluster-wide namespace-create RBAC it requires. OrbStack is torn down
  between sessions.
- **Effort:** S.
- **Depends on:** a persistent cluster (same gate as portability CI).

### Replace bats unit tests where a declarative tool fits
- **What:** re-home `scripts/test/*.bats` (`gen-digests` idempotence + schema,
  `validate.sh` fixture pass/fail, the `report.toml` awk parser guard) onto a
  declarative tool where one fits — `cue` native tests for the digest schema,
  `tofu test` (`.tftest.hcl`) for anything that moves into `cv_oci/tofu/`,
  Chainsaw `script:` leaves only as a last resort.
- **Why:** the Slice 5a mandate retired the bash acceptance harness for
  Chainsaw; bats is the remaining hand-rolled test runner. These are host-tool
  unit tests, not Kubernetes e2e, so Chainsaw is a poor fit — wait until
  OpenTofu (Slice 5c) is in the repo so `tofu test` is on the table.
- **Context:** Slice 5a eng review. Not blocking — bats stays green in the
  meantime; pre-commit keeps running it.
- **Effort:** S.
- **Depends on:** Slice 5c (`cv_oci/tofu/` exists).

### Portability CI check (kind / k3d)
- **What:** scheduled run of `bootstrap.sh` + the Slice 1 pipeline on a vanilla
  kind or k3d cluster.
- **Why:** Rule 4 ("portable to any conformant Kubernetes") is asserted but
  untested until Slice 5. A kind run validates it cheaply and continuously and
  catches OrbStack-specific assumptions early (codex #3: registry-trust bootstrap
  is per-platform node config).
- **Context:** raised in the 2026-08-30 CEO review (S9-b). Higher priority than
  the P3 items because it de-risks the whole portability claim before the amd64
  work.
- **Effort:** M (human) / S (CC).
- **Depends on:** Slice 1 stable.

### zot tag immutability (`http.accessControl`) + a `cv-frontend` retention policy
- **What:** (a) a zot `http.accessControl` policy on `cv` / `cv-frontend` so a
  `PUT` to an existing tag is refused (`401`), while `create` + `delete` stay
  open — the **only** zot mechanism that blocks a tag overwrite; (b) a
  `storage.retention` policy for `cv-frontend` (Slice 7 left it out — every
  `deploy` run pushes a fresh CalVer tag and they accumulate; all point at the
  same reproducible digest, so `keepTags` by `mostRecentlyPushedCount` +
  `pulledWithin`, `deleteReferrers: false` so the signed artifact's referrers
  survive). Do this repo together — both are `cv-frontend` config changes and
  the retention counts want the immutability guarantee to reason about.
- **Why:** anti-rollback. `OCIRepository.spec.ref.semver` + `spec.verify`
  already reject a mutated *artifact* at reconcile; this closes the narrower
  hole where a rebuild of `cv:git-<sha>` with image drift silently derefs the
  running image's manifest (the P14 incident class).
- **Context:** was bundled with retention. **Stale-repo retention shipped in
  Slice 7** (`manifests/zot/configmap.yaml` `storage.retention`, test-repo
  prefixes only — `cv-frontend` deliberately excluded). Immutability was
  deferred by the Slice 7 eng review — on an
  anonymous-only registry `accessControl` is a coarse ACL over *all* traffic
  including the pipeline, and it would `401` the byte-reproducible re-push of
  `cv:git-<sha>` that the `deploy-via-flux` recovery path performs. Probe P14b
  (2026-09-03, `scratchpad`/design-doc probes table) confirmed the mechanism
  works (exact repo key beats `**`; `PUT` existing tag → `401`) and that there
  is **no `:latest` carve-out** and **`deleteUntagged: false` does not gate an
  overwrite** (the deref is inline in the manifest-PUT path, not retention).
- **Gated on:** the **Kyverno slice** landing and being planned (user, this
  session) — Kyverno gives a place to express "the pipeline SA may create but
  not overwrite" as admission policy instead of a blunt anonymous ACL, and
  fixes the recovery-path conflict. See "Kyverno as a portfolio demo policy".
- **Effort:** S (once the identity story exists).
- **Depends on:** Kyverno slice; a rework of the `deploy-via-flux` recovery
  path so it does not overwrite an existing tag.

## P3

### `deploy-via-flux` suite scopes to `.items[0]`, not its own PipelineRun
- **What:** `pipeline-succeeds-and-publishes-a-signed-artifact` and downstream
  steps read `pipelinerun -l cv-oci/acceptance-test=deploy-via-flux
  -o jsonpath='{.items[0]...}'`. PipelineRuns accumulate (fixed `cv-pipeline`
  namespace, no per-run cleanup), so `.items[0]` can be a *prior* succeeded run
  — the suite then passes in seconds without waiting for, or asserting against,
  the run it just created.
- **Why:** a real regression in the new run would not be caught.
- **Fix:** capture the created PipelineRun name from `kubectl create -o name`
  and select on it, or `kubectl delete pipelinerun -l … --field-selector` in a
  preflight step.
- **Context:** noticed 2026-09-03 during the Slice 7 T2 verify (the run it
  spawned, `deploy-via-flux-vbkdq`, did complete + pass when checked directly).
- **Effort:** S.

### Rule 15 exit-test scripts
- **What:** `exit-tests/<component>.md` + a script per component that demonstrates
  removal is possible (e.g. "swap zot for a local OCI dir, pipeline still green").
- **Why:** turns the sharpest rule in the plan from a prose checklist into
  enforced practice.
- **Context:** cherry-pick E2, deferred "write the executables once all
  components are in".
- **Effort:** M → S with CC, one small file+script per component.
- **Depends on:** components existing (Slices 1-7).

### Tekton Trigger on cv_frontend push
- **What:** EventListener + TriggerBinding + webhook secret so `cv_frontend`
  commits auto-run the pipeline.
- **Why:** closes the loop; the pipeline becomes real push-triggered CI.
- **Context:** cherry-pick E5. Self-contained add once signing is stable. The
  webhook receiver is a new attack surface needing a shared secret. (The old
  "needs a separate `cv_gitops` repo so the trigger can't self-fire on deploy
  commits" concern is void post-P5 — the deploy path writes an OCI artifact, not
  a git remote, so a source-repo push trigger has nothing to self-fire on.)
- **Effort:** M → S with CC.
- **Depends on:** Slice 4 (signing) done.

### npm read-through cache keyed by lockfile hash
- **What:** a cache volume for `~/.npm` keyed by `package-lock.json` hash so
  builds skip re-download.
- **Why:** build speed as `cv_frontend` dependencies grow.
- **Context:** raised in the CEO review (S7-c). Safe because `npm ci` is
  lockfile-driven and the cache is content-addressed.
- **Effort:** S.
- **Depends on:** nothing. Do it when build time actually bites.

### Convert pipeline-infra to Timoni modules + Flux (infra under GitOps)
- **What:** re-author the pipeline's own YAML (Tekton Tasks/Pipeline, zot, RBAC,
  cert-manager issuers, Chains config) as Timoni modules reconciled by Flux.
- **Why:** the stated end state — all config as OCI-artifact modules by digest,
  Flux-reconciled.
- **Context:** Slice 5 does only the app (`modules/web-app/`, Flux
  `OCIRepository` for `cv-frontend`). Infra is deferred with an explicit plan in
  `docs/designs/buildpacks-pivot.md` §Slice 5 ("Infra under GitOps — deferred
  plan"): reconcile order cert-manager → issuers → zot(TLS) → Chains → Tekton;
  boundary = `bootstrap.sh` (or `tofu`) installs Flux + cert-manager CRDs + seed
  Secrets, Flux owns downstream. Deferred because each adoption must stay
  bisect-green and a Flux misconfig then breaks zot/Chains too.
- **Effort:** L (a set of small bisect-safe commits).
- **Depends on:** Slice 5b (the `modules/web-app/` pattern proven) + Slice 5c
  (Flux + `cv_oci/tofu/` in place).

### Convert cluster-bootstrap provisioning
- **What:** the pre-Flux base layer (Tekton install, cert-manager, Chains, zot
  seed) moves from `bootstrap.sh` into `cv_oci/tofu/` (OpenTofu), **not** Timoni.
- **Why:** `bootstrap.sh` is frozen (Slice 5 mandate: no new bash). Provisioning
  = OpenTofu; config generation = Timoni. The last imperative bits (secret
  material, Flux's own install) stay minimal.
- **Context:** Slice 5c starts `cv_oci/tofu/` for the Flux layer. This TODO
  extends it to absorb the rest of `bootstrap.sh`, then `bootstrap.sh` is deleted.
- **Effort:** M.
- **Depends on:** Slice 5c (`cv_oci/tofu/` exists) + "Convert pipeline-infra"
  above (so Flux owns what tofu doesn't).

### Migrate `cv_oci/tofu/` to its own repo
- **What:** split the OpenTofu provisioning code out of `cv_oci` into a standalone
  infra repo.
- **Why:** one-concern-per-repo; isolate `tofu` state; keep `cv_oci` about the
  pipeline + app.
- **Context:** Slice 5 keeps `tofu/` in-repo deliberately (small footprint, no
  repo boundary through the Slice 6 reconstruction story). Split when real cloud
  infra appears — amd64 node pools, a managed / hosted registry, DNS, the
  Crossplane / k0rdent direction below. Note the Slice 6 implication:
  `reconstruct.sh` would then cross a repo boundary to regenerate `tofu`-managed
  state.
- **Effort:** M.
- **Depends on:** a real cloud-infra trigger (not time-based).


### `cv_openbao` — transit signing + secrets, its own repo
- **What:** a standalone project: OpenBao (`openbao-distroless` 2.6, raft
  storage, static-key seal) providing (a) cosign transit signing for Tekton
  Chains via `signers.kms` + `hashivault://cosign` + OIDC/JWT auth, (b)
  OpenBao PKI as the zot cert issuer replacing the self-signed `ClusterIssuer`,
  (c) Flux SOPS-via-transit for any future encrypted Flux secret.
- **Why:** the KMS / KMS-backed-signing lesson, done right. cv_oci ships x509
  signing (a K8s Secret + a `debt.md` row) until this exists.
- **Context:** eng review 2026-09-02. Folding OpenBao into cv_oci as "Slice 4b"
  was rejected — it is the least-original, most-stateful item in the
  supply-chain space and would gate the distinctive Slices 5–6 (GitOps +
  reconstruction capstone). One-concern-per-repo, like `cv_packs`.
  Research captured in `docs/designs/buildpacks-pivot.md` §`cv_openbao`. First
  task there: live wire-up of Chains→OpenBao (P6 — OIDC discovery reachability,
  sigstore health-endpoint probe, key-format skew).
- **Effort:** L (own design doc, own bisect-safe history).
- **Depends on:** cv_oci Slice 4 (x509 signing must exist to migrate from);
  a persistent cluster (OrbStack PVs persist — confirmed).

### Crossplane for cloud infra
- **What:** manage cloud resources (amd64 node pools, managed registries, DNS)
  declaratively via Crossplane.
- **Why:** extends the digest/declarative model to infrastructure-as-data.
- **Context:** user named k0s / k0smotron / k0rdent + Crossplane as future
  directions; k0rdent pairs with Crossplane for multi-cluster. Revisit at the
  Slice 5 amd64-node gate — that decision may make Crossplane central or moot.
- **Effort:** XL.
- **Depends on:** Slice 5 (when real nodes / cloud enter the picture).
