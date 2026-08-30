# CEO/Founder-Mode Plan Review — Pipeline Restructure

Reviewed 2026-08-30 · Mode: SELECTIVE EXPANSION · Reviews the design doc
`pipeline-restructure.md` + `plan/`. Outside voice: Codex (gpt-5.6), issues found.

This document is the review record. Decisions here supersede the corresponding
parts of `pipeline-restructure.md` until that doc is rewritten in Slice 0.

## Abstract

The 6-slice restructure is the right shape. The review found no reason to change
the vertical-slice, single-arch-first strategy. It found: a false premise in the
design doc (`remix` has no `build` command), an unreconciled contradiction
between `plan/` and the design doc, three feasibility errors (Chains can't be
consumed in-run, a web server can't smoke-test as a Job, `tkn lint` is not a
command), and ~20 under-specified failure/observability/edge paths. All are
fixable inside the existing slice structure. Net: the plan is sound; Slice 0 and
Slice 1 need substantial detail added before implementation.

## Goals

- Keep the strategy (6 slices, single-arch first, git history as deliverable).
- Make Slice 0 and Slice 1 implementable without mid-slice rework.
- Reconcile the two planning docs into one source of truth.
- Record every accepted compromise with an upgrade trigger.

## Constraints

- Solo learning + portfolio repo. Optimize for one-subsystem-per-commit, not speed.
- OrbStack arm64 only until the amd64 gate (Slice 5).
- Pipeline must stay portable to any conformant Kubernetes; registry-trust
  bootstrap is explicitly per-platform node config (not portable, and that's ok
  if documented).
- No Docker daemon, no Dockerfile, no QEMU (Rule 3), no private Fulcio/Rekor.

---

## What already exists

| Sub-problem | Existing thing | Plan reuses it? |
|---|---|---|
| App to build | `cv_frontend` (`../frontend`), 1 commit `0bbc684`, `remix@3.0.0-beta.10`, Node 24 | Yes — pinned by SHA |
| App build step | **None.** No `remix build`; `createAssetServer` compiles on demand via esbuild at request time | Was assumed to exist; now handled (Option A → Option C) |
| App tests | **None.** `npm test` runs zero test files | Being fixed (2b-A: add a router test) |
| Health route | **None.** Only `/` and `/assets/*path` | Being added (E1) |
| Planning content | `plan/` (10-phase) + `pipeline-restructure.md` (6-slice) | `plan/` deleted, content migrated into design doc |
| Determinism knowledge | `plan/05-reproducibility-and-git.md`, `plan/06-testing-strategy.md` | Migrated into design doc |
| Rule 15 (dependency exit tests) | Prose in `plan/07` | Kept as prose; executable versions → TODO |

---

## Implementation Alternatives (0C-bis) — resolved

The vertical-slice strategy (Approach A) was already chosen and is not
re-litigated. The live decision was the release-tree build step:

- **A (chosen for Slice 1):** Remix asset server runs in the runtime image
  (`watch: false`, `fingerprint: { buildId: APP_SHA }`, warm-on-startup). Runtime
  carries esbuild. Correctness-first; honest Rule 15 exit test.
- **C (Slice 2 target):** snapshot the browser asset graph to static files, serve
  via `staticFiles`, drop request-time bundling.
- **B (rejected for now):** full precompile of server + assets to plain JS.
  Highest determinism, highest correctness risk on a moving beta.

Prerequisite before Slice 1: run "The Assignment" (design doc) with a corrected
command — `remix build` does not exist; run the app from a prod-only
`node_modules` copy with `NODE_ENV=production node --import remix/node-tsx
server.ts` and record what the runtime touches.

---

## Scope decisions (SELECTIVE EXPANSION)

### Accepted into scope

| Id | Item | Slice |
|---|---|---|
| E1 | `/healthz` route + router test in `cv_frontend` | Slice 1 prep |
| E3 | pre-commit hook running offline Tekton schema validation (CM-4-A) | Slice 0 |
| E6 | scheduled reproducibility rebuild (Tekton CronJob, digest-drift alert) | Slice 2 |
| 5c-A | non-trivial shell → checked-in `scripts/` + `scripts/test/` unit layer | Slice 0+ |
| 5d-A | `digests.cue` as the single pinned-digest source of truth | Slice 0 |
| T5-A | flat kustomize bases (no overlays) as throwaway scaffolding | Slices 0-6 |
| 9a-A | ordered `bootstrap.sh` with `--wait` gates | Slice 1 |
| New | **Slice 7 — GitOps handoff** (Timoni app module + Flux, render-and-push flow) | new |
| New | **OpenBao slice** — persistent, Shamir unseal, transit signing (after Slice 7) | new |

### Deferred to TODOS.md

E2 (exit-test scripts), E5 (Tekton Trigger), TODO-3 (npm cache), TODO-4
(portability CI, P2), TODO-5 (pipeline-infra → Timoni), TODO-6 (bootstrap →
Timoni), TODO-7 (Crossplane).

### Skipped / rejected

- E4 as originally accepted (OpenBao dev-mode at Slice 4) — **reverted** per
  CM-2-A; dev-mode OpenBao is strictly worse than a K8s key Secret. OpenBao
  returns as its own persistent slice.
- 10x scope (keyless signing, private Fulcio/Rekor, policy engine, multi-registry
  federation, SLSA L3) — the repo's non-goals list; correctly excluded.

---

## NOT in scope

| Item | Rationale |
|---|---|
| `remix build` / ahead-of-time app build | The framework has no such command; Option A/C handle it |
| cert-manager | Rule 15 — a plain openssl CA Secret covers one internal cert (9f-B); revisit at Slice 7 |
| QEMU / binfmt | Rule 3; Slice 5 uses native amd64 nodes |
| OpenBao dev-mode | CM-2-A — worst of both worlds; persistent OpenBao slice instead |
| Multi-arch shared PVC workspace | codex #2 — RWO can't span nodes; Slice 5 uses per-arch PVCs or pushes each arch straight to zot |
| Baseline-ledger CVE regression gate | CM-6-A — non-deterministic; "policy as of now" + pinned scanner/DB instead |
| Timoni for pipeline-infra + bootstrap | T1 wanted it; deferred to TODO-5/6 as separate arcs |
| Crossplane | TODO-7; no cloud infra exists yet |
| Tekton Trigger / webhook | E5 → TODO-2; manual `tkn start` while learning |

---

## Dream state delta

12-month ideal: signed multi-arch OCI index as release identity, native amd64 +
arm64, CVE-as-of-now gate, SLSA provenance binding both repo SHAs + pinned tool
digests, promote-by-digest, and a GitOps handoff where the deployment config is
itself a signed OCI module reconciled by digest.

This plan reaches: single-arch signed release (Slice 4), multi-arch index (Slice
5), promotion (Slice 6), GitOps config-as-module (Slice 7). The full ideal is the
plan's own endpoint. Gap after Slice 7: pipeline-infra and bootstrap are still
imperative/kustomize (TODO-5/6); amd64 node provisioning is manual until
k0s/k0smotron (TODO-7 territory).

---

## Architecture (Section 1)

Target Slice 1 architecture: see the ASCII diagram in the review conversation
(resolve → build → assemble → smoke → deploy, PVC workspace replacing CubeFS,
in-cluster zot with a self-signed cert).

Decisions:
- **1a:** delete `plan/`; migrate its reference content (glossary, operational
  rules incl. Rule 15, security-model depth, enumerated test list) into the
  design doc; design doc becomes sole source of truth. No information lost.
  Commit zero does this — not "migrate later" (codex #14).
- **1c-A:** `docs/frontend-contract.md` enumerating every assumption the pipeline
  makes about `cv_frontend` layout; `resolve` Task asserts those paths exist at
  `APP_SHA` and fails loud otherwise.
- **1e-A:** `deploy` Task records previous + new digest (ConfigMap / annotation)
  before applying; design doc gets an explicit Rollback section.
- **1d-A:** Slice 1 runs under one ServiceAccount; a dedicated **Slice 1.5**
  commit splits it into least-privilege `build-sa` / `assemble-sa` / `deploy-sa`.
- SPOF note: single zot / node / PVC are acceptable for a learning cluster;
  state it in the architecture doc.

## Error & Rescue Registry (Section 2)

| Codepath | Failure mode | Handled | Test | User/operator sees | Logged |
|---|---|---|---|---|---|
| `resolve` | ref won't resolve / repo unreachable | Y (Rule 13) | 6c-A | Task fails, message names the ref | Y (8a-A) |
| `resolve` | `APP_SHA` not a valid/known sha | Y (4a-A) | 6c-A | "revision X not found in cv_frontend" | Y |
| `resolve` | `cv_frontend` layout drift | Y (1c-A) | contract check | "expected path X missing at SHA" | Y |
| `build` npm ci | lockfile mismatch | Y (npm) | — | npm ci nonzero | Y |
| `build` audit signatures | unsigned/tampered dep | Y | — | Task fails | Y |
| `build` typecheck | tsc error | Y | — | Task fails | Y |
| `build` npm test | **zero tests → hollow pass** | **was N** → Y (2b-A) | router test | real assertion now | Y |
| `build` release tree | empty / degenerate / dev-deps leaked | **was N** → Y (4b-A) | 6c-A | "release tree assertion failed: X" | Y |
| `build` PVC write | PVC full / quota | Partial | — | ENOSPC (cryptic) — add a preflight df check | Y |
| `assemble` | PVC read fail | Y | — | Task fails | Y |
| `assemble` | release-tree digest mismatch (Slice 2+) | Y | 14 | "expected hash X got Y" | Y |
| `assemble` | distroless pull / signature verify fail | Y | plan 06 #6 | Task fails | Y |
| `assemble` | `crane push` — zot down / TLS | **was N** → Y (2a-A) | 6c-A | "cannot reach registry / cert error" | Y |
| `smoke` | image unpullable (node trust) | **was N** → Y (2a-A + CM-3-A) | 6c-A | pull error on the probe Deployment | Y |
| `smoke` | app crash / slow cold start | Y (6d-A gates readiness) | 6c-A | rollout timeout | Y |
| `smoke` | `/healthz` != 200 | Y | 6c-A | "smoke failed: status N" | Y |
| `smoke` | **FAIL-path resource leak** | **was N** → Y (2d-A) | 6c-A | resources GC'd via trap + TTL + `finally` | Y |
| `deploy` | kubelet can't pull | Y (2a-A) | 9e-A | rollout fails | Y |
| `deploy` | rollout stuck / probe fail | Y (9e-A) | — | "rollout did not complete in Ns" | Y |
| `deploy` | applied ≠ smoke-tested digest | Y (S4-d: consume digest result, never re-resolve tag) | — | n/a (prevented) | Y |
| Pipeline | mid-run failure, image already in zot | Note only | — | candidate tag orphaned (expected pre-Slice-6) | Y |
| Chains (Slice 4) | **signs after run; can't be consumed in-run** | Y (CM-1-A: 2nd PipelineRun) | negative test | verify run fails if unsigned | Y |
| Chains (Slice 4) | silent non-signing | Y (8c-A, in the 2nd run) | 8c-A assertion | "no .sig/.att referrer for digest" | Y |
| CVE gate (Slice 3) | Trivy DB drift → non-deterministic verdict | Y (CM-6-A) | fixture tests | "fixable CRITICAL: CVE-… in pkg" | Y |
| Flux (Slice 7) | reconcile / verify fail | Y | negative test | Flux Kustomization not-ready + event | needs a sink |

No `catch (Exception)` smell — no application code. Rule 13 (fail loud, no silent
fallback) is the correct posture and covers most rows.

## Failure Modes Registry — CRITICAL GAPS

After the accepted findings, **zero** rows remain RESCUED=N + TEST=N + SILENT.
Two rows are RESCUED=Partial and need a small addition:

| Codepath | Gap | Fix | Priority |
|---|---|---|---|
| `build` PVC write | ENOSPC is cryptic | preflight `df` check in build Task, fail with "workspace PVC has N MB free, need M" | P2 |
| Flux reconcile (Slice 7) | failures easy to miss | notification-controller → a sink (even just `kubectl events` in a runbook step) | P3 (Slice 7) |

## Security & Threat Model (Section 3)

- **S3-a / 3a-A:** zot unauthenticated Slices 1-5 + a NetworkPolicy scoping
  access to the pipeline namespace; full authz Slice 6. Deploy-by-digest limits
  blast radius.
- **S3-b (inline):** `automountServiceAccountToken: false` on build/assemble/smoke
  from Slice 1; `true` only on deploy.
- **S3-c (accepted risk — record in security-model doc):** runtime image carries
  esbuild (via `remix/node-tsx` + asset server) under Option A. Post-RCE the
  attacker has a bundler; distroless has no shell, partial mitigation. Remediated
  by Slice 2 Option C.
- **S3-d / CM-2-A:** OpenBao removed from Slice 4. Slice 4 signs with a K8s
  cosign key Secret. A later **OpenBao slice** does it properly: persistent
  storage, Shamir unseal, transit engine, cosign KMS URI, its own Rule 15 exit
  test.
- **S3-e (note):** `remix@3.0.0-beta.10` is a beta of an entire framework as the
  sole prod dep. `npm audit signatures` + lockfile pin + Slice 3 CVE gate.
- **Provenance (codex #7):** Chains needs explicit `*_ARTIFACT_INPUTS` type
  hints; a user-supplied `cv_oci` SHA does not prove the running YAML came from
  it. Bind the executed pipeline definition via a **pinned Tekton bundle**, or
  drop the claim that provenance establishes the pipeline commit.

## Data Flow & Edge Cases (Section 4)

- **4a-A:** `resolve` Task accepts a full sha or a ref, resolves ref→sha via
  `ls-remote`, verifies existence in `cv_frontend`, echoes `APP_SHA`, fails loud.
- **4b-A:** `build` Task asserts the release tree contains `server.ts`, `app/`,
  `node_modules/remix`, `package.json`, is above a floor size, and does NOT
  contain `typescript` / `@types/node`. Fails before PVC handoff.
- **4e-A:** per-run workspace subdir (`/release/<pipelinerun>/app`) from Slice 1;
  Slice 5 extends to `/release/<run>/<arch>/app` — but see codex #2: cross-node
  arm64+amd64 needs per-arch PVCs or each arch pushing straight to zot, not a
  shared volume.
- **S4-d (inline):** `deploy` consumes the digest Task result, never re-resolves
  the candidate tag.

## Test Review (Section 6)

- **6a-A:** `scripts/test/` unit layer (bats or shell asserts) for every
  `scripts/*` file; run by the Slice 0 pre-commit hook and CI.
- **6c-A:** Slice 1 ships four negative tests — bad `APP_SHA`, degenerate release
  tree, `/healthz` != 200 (+ teardown runs), zot unreachable.
- **6d-A:** the app's readiness only reports true after the startup warm
  completes; smoke waits for Ready then probes with a normal timeout. No
  timing-dependent test.
- **codex #13:** each `cv_oci` commit pins a known-good `cv_frontend` fixture SHA
  (in `digests.cue` or a `frontend-fixture.sha`) so acceptance is meaningful at
  any checkout, not dependent on mutable external knowledge.

## Performance (Section 7)

No decision-worthy findings. Notes: first-request bundling ~1-3s (mitigated by
6d-A, removed by Slice 2 Option C); image ~200-350MB; `npm ci` cold each run
(TODO-3).

## Observability (Section 8)

- **8a-A:** scripts emit `key=value` log lines at entry/exit/decision; raise
  PipelineRun retention (or a keep-N pruner); the 1e-A ConfigMap also records
  `APP_SHA` + digest + timestamp + PipelineRun name → doubles as "what's
  deployed" + rollback source.
- **8b-A:** `docs/runbook.md`, one entry per failure mode, grows per slice.
- **8c-A:** in the CM-1-A verification PipelineRun, assert the `.sig` +
  attestation referrers exist in zot for the digest; fail loud if absent.

## Deployment & Rollout (Section 9)

- **9a-A:** `scripts/bootstrap.sh` applies in dependency order with `--wait`
  between phases (CRDs → operators ready → CA → zot → pipeline); idempotent;
  documented in the runbook. (Crossplane noted for the future, not now.)
- **9e-A:** `deploy` Task runs `kubectl rollout status --timeout` then probes
  `/healthz` through the Service; fails the Task on either.
- **9f-B:** plain openssl CA Secret for Slices 1-6, manual rotation documented;
  revisit cert-manager at Slice 7.
- **CM-4-A:** Slice 0 validation = offline schema check (kubeconform + pinned
  Tekton CRD schemas). `kubectl apply --dry-run=server` is a separate post-
  bootstrap check.

## Long-Term Trajectory (Section 10)

- Reversibility: plan 5/5, built system 4/5.
- **10a-A:** design doc gets an explicit "Slice 5 entry gate: amd64 node decision
  made and node joined" with the option list (k0s/k0smotron/k0rdent on OrbStack
  VMs / managed dual-pool / QEMU+drop Rule 3) and "revisit before Slice 5".
- **10b-A:** `docs/debt.md` ledger — one row per accepted compromise:

| Compromise | Why accepted | Upgrade when | Target |
|---|---|---|---|
| Option A: compiler in runtime image | correctness-first on a beta framework | request-time bundling proves a determinism or security problem | Slice 2 → Option C |
| Flat kustomize scaffolding | Timoni end state not proven yet | Slice 7 lands | Slice 7 → Timoni |
| Slice 4 signs with a K8s key Secret | dev-mode OpenBao is worse; persistent OpenBao is its own arc | you want the KMS/transit lesson | OpenBao slice |
| Plain openssl CA Secret, manual rotation | Rule 15 — one internal cert | cert automation actually needed | Slice 7 revisit |
| `npm ci` cold every build | 1-dep app, cache = determinism variable | build time bites | TODO-3 |
| Rule 4 portability untested | no 2nd cluster yet | before Slice 5 | TODO-4 (kind CI) |
| Registry-trust bootstrap is per-platform | K8s treats it as node config; unavoidable | — | documented caveat, not fixed |

## Design & UX (Section 11)

SKIPPED — no UI scope.

---

## Diagrams

### 1. System architecture (Slice 1)

```
 cv_frontend@APP_SHA ──┐
                       ▼
   resolve ─▶ build ─▶ [PVC /release/<run>/app] ─▶ assemble ─▶ smoke ─▶ deploy
   (validate  (npm ci,   RW build / RO assemble    (crane      (temp     (rollout
    +verify   audit,                                 append,    Deploy+   status +
    +echo)    typecheck,                             push to    Service+  /healthz
             test, tree                              zot via    probe     via Svc)
             assertion)                              TLS)       Pod)
                                                       │
                                              zot (in-cluster, self-signed cert,
                                              unauth + NetworkPolicy, PVC storage)
```

### 2. Data flow + shadow paths

```
 APP_SHA ─▶ clone ─▶ npm ci --omit=dev ─▶ tree assert ─▶ PVC ─▶ crane append ─▶ push
   │          │           │                   │           │         │            │
 nil/branch  SHA gone   network flake     empty tree   PVC full  base pull    zot down
 → 4a-A     → 4a-A      → Rule 13 fail    → 4b-A fail   → df      → Rule 13    → 2a-A
   fail       fail                                       preflight  fail         fail
```

### 3. State machine — release candidate (post-Slice-4, two PipelineRuns)

```
   (build run)                    (Chains, async)         (verify+deploy run)
 QUEUED ─▶ BUILDING ─▶ ASSEMBLED ─────────────────▶ SIGNED ─▶ VERIFYING ─▶ DEPLOYED
             │             │                          │           │
             ▼             ▼                          ▼           ▼
          BUILD_FAIL   ASSEMBLE_FAIL          SIGN_MISSING    VERIFY_FAIL
          (no push)    (no push)              (8c-A catches)  (unsigned/mismatch
                                                               → no deploy)

 impossible: DEPLOYED without SIGNED (verify run gates it)
 impossible: SIGNED before build run completes (Chains lifecycle — CM-1-A)
```

### 4. Error flow

```
 any Task step nonzero
   │
   ├─ script emits key=value error line (8a-A)
   ├─ Task fails ─▶ PipelineRun fails ─▶ `finally` teardown (2d-A)
   │                                       └─ smoke resources GC'd (trap + TTL)
   └─ candidate image may already be in zot (orphan tag, expected pre-Slice-6)

 Chains failure (Slice 4): does NOT fail the build run (codex #1)
   └─ 8c-A referrer assertion in the verify run catches it ─▶ verify run fails
```

### 5. Deployment sequence (bootstrap.sh, 9a-A)

```
 phase 1: apply CRDs (Tekton)              ─▶ wait --for=condition=Established
 phase 2: apply Tekton controllers         ─▶ wait --for=condition=Available
 phase 3: apply CA Secret + zot cert       ─▶ (no wait)
 phase 4: apply zot Deployment + Svc + PVC ─▶ wait --for=condition=Available
 phase 5: apply NetworkPolicy + Pipeline/Tasks/RBAC/SA
 phase 6: (Slice 1+) kubectl apply --dry-run=server over the applied YAML
```

### 6. Rollback flowchart

```
 deploy of digest D_new breaks
   │
   ▼
 read deploy-state ConfigMap ─▶ D_prev (1e-A)
   │
   ▼
 kubectl set image deploy/cv cv=zot.svc/cv@D_prev   (or `kubectl rollout undo`)
   │
   ▼
 wait rollout status ─▶ probe /healthz ─▶ update ConfigMap (current = D_prev)
   │
   ▼
 file a debt.md / runbook note: why D_new failed
```

## Stale Diagram Audit

| Diagram | File | Status |
|---|---|---|
| System overview (CubeFS, matrix, amd64+arm64) | `plan/01-architecture.md:11` | **STALE** — CubeFS gone, single-arch first; deleted with `plan/` |
| Pipeline stages | `plan/03-pipeline-design.md:5` | **STALE** — no artifact-seal stage, no matrix in Slice 1; deleted with `plan/` |
| Trust chain | `plan/04-security-model.md:9` | **STALE** — "Node builder digest" framing, index-digest-from-commit-1; migrate corrected version into design doc |
| Reproducibility artifact graph | `plan/05-reproducibility-and-git.md:7` | **STALE** — amd64+arm64 trees from commit 1; migrate corrected version |
| Primary invariant | `plan/README.md:41` | **STALE** — lists amd64+arm64 as commit-1 gates; corrected in design doc |
| design doc has no diagrams | `pipeline-restructure.md` | needs the 6 diagrams above added during the Slice 0 rewrite |

---

## Implementation Tasks

Synthesized from this review. Each derives from a specific finding. P1 blocks the
slice it belongs to; P2 same-slice; P3 is a follow-up.

- [ ] **T1 (P1, human ~1h / CC ~15m)** — cv_frontend — Run "The Assignment" with the corrected command
  - Surfaced by: 0C-bis / design doc premise — `remix build` does not exist
  - Files: none (investigation); write findings into the design doc
  - Verify: a written note stating what files the runtime touches + whether esbuild runs at request time
- [ ] **T2 (P1, human ~half day / CC ~25m)** — docs — Rewrite `pipeline-restructure.md` as sole source of truth; delete `plan/` (migrate glossary, Rule 15, security depth, test list); add the 6 diagrams
  - Surfaced by: 1a, codex #14 — two contradictory docs, none authoritative
  - Files: `docs/designs/pipeline-restructure.md`, delete `plan/`
  - Verify: `plan/` gone; design doc contains every reference section; `rg -n "remix build|CubeFS|slsa/v2\b" docs/` returns nothing
- [ ] **T3 (P1, human ~2h / CC ~15m)** — Slice 0 — `digests.cue` + `cue export` wiring
  - Surfaced by: 5d-A
  - Files: `digests.cue`, `scripts/lib/digests.sh`
  - Verify: `cue vet digests.cue`; a script sources a digest via `cue export`
- [ ] **T4 (P1, human ~3h / CC ~20m)** — Slice 0 — offline Tekton schema validation + pre-commit hook
  - Surfaced by: E3, CM-4-A, codex #9 — `tkn lint` is not a command
  - Files: `scripts/validate.sh`, `.git/hooks/pre-commit` (or `justfile` target), pinned CRD schemas under `schemas/`
  - Verify: hook rejects a deliberately-broken Task YAML; passes on valid YAML with no cluster
- [ ] **T5 (P1, human ~2h / CC ~15m)** — cv_frontend — `/healthz` route + router test
  - Surfaced by: E1, 2b-A, design doc Open Q5
  - Files: `cv_frontend`: `app/routes.ts`, `app/actions/health.tsx` (or similar), `app/*.test.ts`
  - Verify: `npm test` in cv_frontend asserts `GET /healthz` → 200 and `GET /` → 200
- [ ] **T6 (P1, human ~2h / CC ~15m)** — Slice 1 — `resolve` Task: validate + resolve + verify + echo `APP_SHA`
  - Surfaced by: 4a-A
  - Files: `scripts/resolve-sha.sh`, `tasks/resolve.yaml`, `scripts/test/resolve-sha.bats`
  - Verify: bad sha → nonzero with a clear message; branch → resolved full sha echoed
- [ ] **T7 (P1, human ~2h / CC ~15m)** — Slice 1 — `build` Task release-tree assertion gate
  - Surfaced by: 4b-A, S4-c
  - Files: `scripts/assert-release-tree.sh`, `tasks/build.yaml`, `scripts/test/assert-release-tree.bats`
  - Verify: empty tree fails; tree with `typescript/` fails; valid tree passes
- [ ] **T8 (P1, human ~1h / CC ~10m)** — Slice 1 — per-run PVC workspace subdir
  - Surfaced by: 4e-A
  - Files: `pipeline/pipeline.yaml`, `tasks/build.yaml`, `tasks/assemble.yaml`
  - Verify: two concurrent PipelineRuns don't collide (distinct subdirs)
- [ ] **T9 (P1, human ~1 day / CC ~30m)** — Slice 1 — zot self-signed cert + CA trust + registry-trust bootstrap doc
  - Surfaced by: 2a-A, codex #3
  - Files: `bootstrap/ca/`, `zot/`, `docs/registry-trust.md`
  - Verify: `crane push` from a Task succeeds over HTTPS; kubelet pulls the pushed digest; doc states the per-platform node-trust step
- [ ] **T10 (P1, human ~half day / CC ~20m)** — Slice 1 — smoke as temp Deployment + Service + probe Pod, with always-run teardown
  - Surfaced by: CM-3-A, codex #11, 2d-A
  - Files: `scripts/smoke.sh`, `tasks/smoke.yaml`, `pipeline/pipeline.yaml` (`finally`)
  - Verify: healthy image → smoke passes + resources gone; broken image → smoke fails + resources gone
- [ ] **T11 (P1, human ~2h / CC ~15m)** — Slice 1 — `deploy` Task: rollout status + `/healthz` via Service + record digest
  - Surfaced by: 9e-A, 1e-A, S4-d
  - Files: `scripts/deploy.sh`, `tasks/deploy.yaml`, deploy-state ConfigMap manifest
  - Verify: crash-loop image → deploy Task fails; success → ConfigMap has prev+new digest
- [ ] **T12 (P1, human ~3h / CC ~20m)** — Slice 1 — `bootstrap.sh` with ordered `--wait` phases
  - Surfaced by: 9a-A
  - Files: `scripts/bootstrap.sh`, `kustomize/` bases
  - Verify: on a fresh OrbStack cluster, one run brings everything up; re-run is a no-op
- [ ] **T13 (P1, human ~1 day / CC ~30m)** — Slice 1 — four negative tests
  - Surfaced by: 6c-A
  - Files: `scripts/test/` or `tests/pipeline/`
  - Verify: each of bad-SHA / degenerate-tree / smoke-fail / zot-down produces a red pipeline at the right stage
- [ ] **T14 (P2, human ~2h / CC ~15m)** — Slice 1 — structured logging + PipelineRun retention + deploy-state ConfigMap
  - Surfaced by: 8a-A
  - Files: `scripts/lib/log.sh`, Tekton config, ConfigMap manifest
  - Verify: a failed run's logs are readable a day later; ConfigMap answers "what's deployed"
- [ ] **T15 (P2, human ~2h / CC ~15m)** — cv_oci — `docs/frontend-contract.md` + `resolve` preflight path assertion
  - Surfaced by: 1c-A
  - Files: `docs/frontend-contract.md`, `scripts/resolve-sha.sh`
  - Verify: rename `server.ts` in a test clone → resolve fails with "expected path missing"
- [ ] **T16 (P2, human ~1h / CC ~10m)** — cv_oci — pin a known-good `cv_frontend` fixture SHA per commit
  - Surfaced by: codex #13
  - Files: `digests.cue` (or `frontend-fixture.sha`)
  - Verify: `npm test`/acceptance at an arbitrary checkout uses the pinned fixture, not "latest"
- [ ] **T17 (P2, human ~1h / CC ~10m)** — Slice 1 — `automountServiceAccountToken: false` on build/assemble/smoke
  - Surfaced by: S3-b
  - Files: `tasks/*.yaml` / SA manifests
  - Verify: those pods have no SA token mounted; deploy still does
- [ ] **T18 (P2, human ~30m / CC ~5m)** — Slice 1 — build Task PVC `df` preflight
  - Surfaced by: Failure Modes Registry gap
  - Files: `scripts/assert-release-tree.sh` (or a new preflight step)
  - Verify: a near-full PVC → "workspace has N MB free, need M" not raw ENOSPC
- [ ] **T19 (P2, human ~2h / CC ~15m)** — Slice 1.5 — split the single SA into least-privilege per-stage SAs
  - Surfaced by: 1d-A
  - Files: `rbac/`, `tasks/*.yaml`, `pipeline/pipeline.yaml`
  - Verify: `build-sa` cannot push to zot; `deploy-sa` cannot write the workspace
- [ ] **T20 (P2, human ~1h / CC ~10m)** — Slice 1 — NetworkPolicy scoping zot access
  - Surfaced by: 3a-A
  - Files: `zot/networkpolicy.yaml`
  - Verify: a pod outside the pipeline namespace cannot reach zot; pipeline pods can
- [ ] **T21 (P3, human ~2h / CC ~15m)** — docs — `docs/debt.md` + `docs/runbook.md` scaffolds, grow per slice
  - Surfaced by: 10b-A, 8b-A
  - Files: `docs/debt.md`, `docs/runbook.md`
  - Verify: both exist with the Slice 0/1 rows/entries from this review
- [ ] **T22 (P3, human ~1h / CC ~10m)** — design doc — add "Slice 5 entry gate: amd64 node decided + joined" with option list
  - Surfaced by: 10a-A, design doc Open Q4
  - Files: `docs/designs/pipeline-restructure.md`
  - Verify: Slice 5 section opens with the gate and the k0s/k0smotron/managed/QEMU options
- [ ] **T23 (P3, human ~1h / CC ~10m)** — design doc — rewrite Slice 4 for the two-PipelineRun Chains flow + correct config strings
  - Surfaced by: CM-1-A, codex #1/#7/#8
  - Files: `docs/designs/pipeline-restructure.md`
  - Verify: Slice 4 text says `slsa/v2alpha4`, `storage.oci.encoding-format=sigstore-bundle`, no-tlog verify, `*_ARTIFACT_INPUTS`, pinned Tekton bundle, and a separate verify+deploy run
- [ ] **T24 (P3, human ~1h / CC ~10m)** — design doc — rewrite Slice 3 CVE gate per CM-6-A; rewrite Slice 5 workspace per codex #2; rewrite Slice 7 per CM-5-A; add the OpenBao persistent slice
  - Surfaced by: CM-6-A, codex #2, CM-5-A, CM-2-A
  - Files: `docs/designs/pipeline-restructure.md`
  - Verify: each slice section matches the decisions in this review record
- [ ] **T25 (P3)** — TODOS.md — E2, E5, TODO-3, TODO-4 (P2), TODO-5, TODO-6, TODO-7
  - Surfaced by: cherry-pick + TODO ceremonies
  - Files: `TODOS.md`
  - Verify: seven entries with What/Why/Context/Effort/Priority/Depends-on

## Eng Review addendum (2026-08-30, scope: Slice 0 + Slice 1 + Slice 4 arch pass)

- **A1-A:** use Tekton built-ins, don't reinvent. Per-run isolation =
  `volumeClaimTemplate` workspace binding (supersedes 4e-A's manual subdir).
  Clone = tektoncd catalog `git-clone` (the `resolve` Task wraps it + adds SHA
  verify + frontend-contract assertion). Pipeline definition delivered via the
  **bundles/git resolver** so the executed digest is provable — this is codex
  #7's "pinned Tekton bundle" for provenance, for free.
- **A2-A:** Slice 4's build run and verify+deploy run are linked by a Tekton
  Trigger + Interceptor filtering PipelineRun events for
  `chains.tekton.dev/signed=true` + success. Pulls the Triggers component into
  Slice 4 (its own Rule 15 entry); the same infra later serves TODO-2.
- **A3-A:** checked-in `scripts/` ship in a pinned `pipeline-utils` OCI image
  (sh, git, crane, cue, trivy, cosign + scripts baked at a known path), built
  **once out-of-cluster by `bootstrap.sh`** and pushed to zot by digest (breaks
  the chicken-egg: the pipeline can't build its own tooling image). Tasks
  reference it by digest.
- **A4-A:** `digests.cue` is source; a Slice 0 script `cue export`s it to a
  committed `digests.env` (scripts + `envsubst` on manifests) and a committed
  Tekton `params.yaml` (Task/Pipeline param defaults). CI regenerates and diffs
  to catch a stale commit.
- **CQ1/CQ2 (inline):** scripts = `bash` + `set -euo pipefail` + `shellcheck`;
  Task boilerplate (securityContext, image ref, token automount) in a
  `stepTemplate`; every script sources `scripts/lib/log.sh`.
- **CQ3-A:** no bespoke deploy-history store. Rollback = `kubectl rollout
  history`/`undo`; a single-value ConfigMap holds the current
  digest+APP_SHA+PipelineRun pointer; the durable audit trail is the signed
  provenance in zot (Slice 4+).
- **T-1-A:** `scripts/test/e2e.sh` runs the real pipeline against live OrbStack
  with a pinned fixture APP_SHA, asserts the three Slice 1 success criteria,
  self-cleans. Manual now, wired into the kind CI at TODO-4. This is the Slice 1
  acceptance test, executable.
- **T-2-A:** `resolve-sha.sh` ref resolution tested against a local bare-repo
  fixture (`scripts/test/fixtures/frontend.git`, `CV_FRONTEND_REMOTE` override);
  one clearly-labelled `@network` test checks the real pinned SHA still exists.
- **Perf:** no findings. `volumeClaimTemplate` churns a local-path PV per run on
  OrbStack — set a size + cleanup retention.

Eng-review implementation tasks (append to the list above):
- [ ] **T26 (P1)** — Slice 1 — `resolve` Task = wrap catalog `git-clone` + SHA-verify + contract-assert; workspace = `volumeClaimTemplate` (replaces T8's manual subdir)
- [ ] **T27 (P1)** — Slice 0/1 — `bootstrap.sh` builds + pushes the pinned `pipeline-utils` image (sh/git/crane/cue/trivy/cosign + scripts) before the pipeline runs
- [ ] **T28 (P1)** — Slice 0 — `cue export` wiring: `digests.cue` → committed `digests.env` + `params.yaml` + CI drift check (extends T3)
- [ ] **T29 (P1)** — Slice 1 — `scripts/test/e2e.sh` (live-cluster acceptance test) + `scripts/test/fixtures/frontend.git` bare-repo fixture
- [ ] **T30 (P2)** — Slice 1 — Tekton `stepTemplate` for shared Task boilerplate; `scripts/lib/log.sh` sourced everywhere
- [ ] **T31 (P2)** — Slice 4 (design) — pipeline definition via bundles/git resolver; Trigger + Interceptor on `chains.tekton.dev/signed` linking the two runs
- [ ] **T32 (P3)** — CQ3-A — drop the deploy-history ConfigMap design; document rollback via `kubectl rollout history` + single-value pointer ConfigMap + zot provenance

## Eng-review outside voice (Codex, 2026-08-30) — resolutions

Codex found the eng-review decisions were too optimistic. All four tensions
resolved toward accept (feasibility catches, not judgment calls):

- **CM-E1-A** — A2-A's "Trigger on the Chains signed-annotation" is infeasible
  (no event fires for a post-completion metadata change; Triggers is HTTP-only).
  Replacement: EventListener fires on build-run **success** (label-filtered);
  the verify+deploy run re-fetches the source PipelineRun by name+UID, polls zot
  for the `.sig`/`.att` referrers with a bounded timeout, runs `cosign verify` +
  `verify-attestation` itself (the run is the trust boundary, not the event
  payload), and is idempotent on a deterministic build-UID key against
  CloudEvent replay. NetworkPolicy + narrow RBAC on the EventListener.
- **CM-E2-A** — "bundles/git resolver" was not a decision. Pick the **git
  resolver**. Pinning the Pipeline does NOT pin its Tasks (cluster-local
  `taskRef.name` stays mutable) — so every Task is either inlined (the small
  custom ones) or git-resolved by commit (catalog `git-clone`). Beta resolver
  feature flags enabled as a Slice 1 bootstrap step. The provenance binding is
  an **acceptance test** (Slice 4): parse the signed SLSA predicate, assert its
  `refSource` entries name the expected Pipeline + every Task URI/digest — not
  "for free".
- **CM-E3-A** — A3-A's bootstrap chicken-egg was moved, not solved. Deliverable:
  `docs/bootstrap-toolchain.md` pinning the exact host CLIs + versions
  `bootstrap.sh` needs (cue, crane, cosign, kubectl, git, openssl) before
  anything in-cluster exists. Two-phase digest flow: phase 0 builds
  `pipeline-utils` + captures its digest; phase 1 writes that digest into
  `digests.cue`; CI recomputes a content-hash of the image inputs and fails on a
  stale recorded digest (the digest is both an input and an output — needs the
  explicit flow). `pipeline-utils` is **arm64-only** for now; a multi-arch index
  is a TODO gated on the kind-CI work.
- **CM-E4-A** — T-1-A / T-2-A harness hardening, all accepted:
  - unique per-run namespace `cv-e2e-<uid>` + zot repo prefix; select resources
    by PipelineRun UID (a shared name can clobber real state; stale pods can
    satisfy `/healthz`).
  - before teardown, dump PipelineRun YAML + Task logs + events + pod describes +
    resolver/Chains status to an artifacts dir (evidence survives cleanup).
  - assertions: PipelineRun success; cloned HEAD == `APP_SHA`; Task-result digest
    exists in zot; Deployment + running Pod `imageID` match that digest;
    `kubectl get deploy -o yaml` shows `@sha256` not a tag; cleanup runs after a
    forced failure.
  - "self-cleans" corrected: delete the per-run zot repo + trigger GC (deleting
    K8s resources leaves blobs/manifests/referrers).
  - the `resolve-sha.sh` git fixture is served by a tiny in-cluster git-http
    Deployment (a host `file://` repo is invisible inside Task pods); the one
    `@network` test that checks the real pinned SHA stays labelled.
- **Also fold (P1, no tension):** PVC lifecycle — pin the Tekton version + set
  `coschedule` mode explicitly; any PVC pruner must wait for Chains signing or it
  deletes the run before Chains snapshots it. Generated-file hardening — pin the
  CUE generator version, whitelist `envsubst` vars, fail on unresolved
  placeholders, server-validate rendered YAML, lint consumers for hard-coded
  tags/digests (a regen-diff only proves the files agree with the generator).

Eng-review outside-voice tasks (append):
- [ ] **T33 (P0)** — Slice 4 design — replace the signed-annotation Trigger with success-trigger + verify-run-polls-and-verifies + idempotent UID key + EventListener NetworkPolicy/RBAC
- [ ] **T34 (P1)** — Slice 1 — pick git resolver; inline small Tasks, git-resolve `git-clone` by commit; enable resolver feature flags in `bootstrap.sh`
- [ ] **T35 (P1)** — Slice 4 — acceptance test: signed SLSA predicate `refSource` names the expected Pipeline + Task URIs/digests
- [ ] **T36 (P1)** — Slice 0 — `docs/bootstrap-toolchain.md` (pinned host CLI versions) + two-phase `pipeline-utils` digest flow + CI input-hash drift check
- [ ] **T37 (P1)** — Slice 1 — e2e harness hardening: per-run namespace/repo/UID isolation, pre-teardown evidence capture, full assertion set, per-run zot repo + GC
- [ ] **T38 (P1)** — Slice 1 — in-cluster git-http Deployment serving the `resolve-sha.sh` test fixture
- [ ] **T39 (P2)** — Slice 1/2 — PVC lifecycle: pin Tekton version + `coschedule`; PVC pruner waits for Chains
- [ ] **T40 (P2)** — Slice 0 — generated-file hardening (CUE version pin, envsubst whitelist, fail-on-unresolved, server-validate, consumer lint)

## Worktree parallelization

| Step | Modules | Depends on |
|------|---------|------------|
| S0-docs | `docs/`, `plan/` (delete) | — |
| S0-tooling | `digests.cue`, `scripts/` (validate, lib), `schemas/` | — |
| S1-frontend | `cv_frontend` repo (`/healthz`, router test, warm-on-ready) | — |
| S1-scripts | `scripts/` (resolve, assert, smoke, deploy, bootstrap) + `scripts/test/` | S0-tooling |
| S1-manifests | `tasks/`, `pipeline/`, `zot/`, `bootstrap/ca/`, `rbac/`, `kustomize/` | S0-tooling |
| S1-e2e | `scripts/test/e2e.sh`, `scripts/test/fixtures/` | S1-scripts, S1-manifests |

- **Lane A:** S0-docs → (nothing) — independent, fast.
- **Lane B:** S0-tooling → S1-scripts → S1-e2e (sequential, shared `scripts/`).
- **Lane C:** S1-frontend (independent — different repo entirely).
- **Lane D:** S1-manifests (depends on S0-tooling for `params.yaml`; otherwise independent of `scripts/`).

Execution: launch A + B + C + D. B and D both consume `digests.env`/`params.yaml`
from S0-tooling — do S0-tooling first, then B and D run in parallel worktrees, C
runs anytime. S1-e2e waits for B and D to merge.
**Conflict flag:** B (S1-scripts) and A3-A's `pipeline-utils` build touch the
same tool list — keep the `pipeline-utils` Dockerfile-equivalent in Lane D
(manifests/build), not Lane B.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 1 | issues_open | SELECTIVE EXPANSION; 4 accepted expansions, 7 deferred, 1 reverted (E4); ~28 findings across 10 sections; 0 critical gaps |
| Codex Review | `/codex` (outside voice) | Independent 2nd opinion | 2 | issues_found | CEO pass: 14 missed blockers, 6 tensions. Eng pass: 16 findings (6 P0), 4 tensions. All resolved toward accept |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | issues_open | SCOPE_REDUCED (Slice 0+1+Slice4 arch); 7 findings + 4 codex tensions, all folded; 0 critical gaps; ~40 impl tasks (2 P0) |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | n/a | no UI scope |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | — | not run |

- **CODEX:** CEO pass caught Chains-can't-be-consumed-in-run, Job-as-smoke-test, nonexistent `tkn lint`, non-deterministic CVE gate, dev-mode OpenBao. Eng pass caught the signed-annotation Trigger being infeasible (no event fires), the pipeline-utils bootstrap chicken-egg being moved not solved, Pipeline-pinning-not-pinning-Tasks, and e2e isolation/cleanup gaps. Two high-value passes.
- **CROSS-MODEL:** both models agree the 6→8 slice strategy is sound. Every disagreement was feasibility detail the Claude review missed, never direction. All 10 tensions across both passes resolved toward the outside voice.
- **VERDICT:** CEO + ENG reviews complete. Both `issues_open` — the plan is NOT ready to implement as the design doc currently reads; it is ready once the P0/P1 tasks fold into a rewritten design doc (T2). No blocking eng-gate remains at the review level — the findings are folded, the work is enumerated. Recommended path: implement Slice 0 (which includes T2, the doc rewrite) first; the rewritten doc is the clean input to Slice 1.

**UNRESOLVED DECISIONS:**
- amd64 node source (design doc Open Q4) — deliberately deferred to the Slice 5 entry gate (10a-A), not resolved now
