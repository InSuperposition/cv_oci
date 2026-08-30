# TODOS

Deferred work. Distinct from `docs/debt.md` (accepted compromises with upgrade
triggers) — this is new work not yet scheduled into a slice.

## P2

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

### Multi-arch pipeline-utils image
- **What:** publish the `pipeline-utils` OCI image as a multi-arch index
  (amd64 + arm64) instead of arm64-only.
- **Why:** the portability CI (above) and Slice 5's amd64 work both need the
  pipeline tooling image to run on amd64.
- **Context:** raised in the 2026-08-30 eng review (CM-E3-A). arm64-only is fine
  while OrbStack is the only cluster. Mild circularity: the first multi-arch
  `pipeline-utils` is probably hand-assembled with `crane` from two arch bases,
  before the pipeline itself does multi-arch assembly (Slice 5).
- **Effort:** M.
- **Depends on:** "Portability CI check" above / Slice 5.

## P3

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
- **Context:** cherry-pick E5. Self-contained add once signing is stable. Note the
  webhook receiver is a new attack surface needing a shared secret.
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

### Convert pipeline-infra to Timoni modules
- **What:** re-author the pipeline's own YAML (Tekton Tasks/Pipeline, zot, RBAC)
  as CUE / Timoni modules.
- **Why:** the stated end state — all config as OCI-artifact modules by digest.
- **Context:** T1 wanted Timoni for app + infra + bootstrap. Slice 7 does only the
  app; infra is its own arc. A whole set of slices when you get there (CUE for
  20+ Tekton resources).
- **Effort:** L.
- **Depends on:** Slice 7 (Timoni + Flux proven for the app).

### Convert cluster-bootstrap to Timoni modules
- **What:** the base layer (Tekton install, Chains install, CA, Flux) as Timoni
  modules.
- **Why:** complete the all-config-as-modules end state.
- **Context:** T1. Usually the last thing converted; bootstrap has chicken-egg
  constraints (Flux can't reconcile its own install), so some of `bootstrap.sh`
  stays imperative by necessity.
- **Effort:** L.
- **Depends on:** "Convert pipeline-infra to Timoni modules" above.

### Crossplane for cloud infra
- **What:** manage cloud resources (amd64 node pools, managed registries, DNS)
  declaratively via Crossplane.
- **Why:** extends the digest/declarative model to infrastructure-as-data.
- **Context:** user named k0s / k0smotron / k0rdent + Crossplane as future
  directions; k0rdent pairs with Crossplane for multi-cluster. Revisit at the
  Slice 5 amd64-node gate — that decision may make Crossplane central or moot.
- **Effort:** XL.
- **Depends on:** Slice 5 (when real nodes / cloud enter the picture).
