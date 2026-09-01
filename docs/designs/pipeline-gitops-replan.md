# cv_oci — Tooling consolidation + zot seed + probe-before-replan (proposal)

Status: SUPERSEDED by `docs/designs/buildpacks-pivot.md` (2026-09-01).
This proposal re-planned the `crane`/`apko` pipeline; that whole premise was
retired in the Cloud Native Buildpacks pivot. Its verified deltas that still
apply (the zot seed with the two-address OrbStack finding; the Chains build-run
+ separate verify+deploy-run split) are carried into `buildpacks-pivot.md`. The
frozen items (regctl-for-assembly, Flux-forward, Tekton bundles, OpenBao-forward,
Flagger, probes P1–P7) are moot — they were about tools this pivot no longer
uses. Do not plan against this doc.

Prior status: PROPOSAL — scaled back after the Opus outside-voice pass found
approach C's specifics rested on unverified tool behaviour.
Supersedes on merge: only the `check-toolchain.sh` / `gen-digests.sh` tooling
choices and the Slice 1.5 content (SAs → zot) in `pipeline-restructure.md`.
Everything else in the SSOT **stands unchanged** until the probes land.
Triggered by: `/plan-eng-review` → `/plan-ceo-review` → Opus outside voice,
2026-09-01.

---

## Abstract

Three reviews ran: eng, CEO (approach C), and an Opus outside voice. The outside
voice verified every load-bearing tool claim against upstream docs — which
neither earlier review did — and found that **3 of the 5 headline tool swaps and
the central Flux re-sequencing claim are factually wrong**:

- `regctl image mod` has no `--config-user` / `--config-workdir`, so it cannot
  reproduce `crane mutate -u 65532 -w /app`. The "no behaviour change" commit
  would take the running app down (`runAsNonRoot` + empty image USER → kubelet
  refuses the container).
- Pod Security `baseline` **forbids** `hostPort` — the label the CEO review
  mandated for the zot seed rejects the zot pod.
- Flux `OCIRepository.spec.verify` verifies the **config artifact's signature
  only** — not the app image, not attestations, not the SLSA predicate — and
  retries **indefinitely** rather than failing loud. It is not a drop-in for the
  separate verify+deploy PipelineRun (Codex CM-1-A).

So this proposal keeps only what is verified or cheap-and-safe, and gates the
rest behind a **probe commit series**. What lands now: **mise**, a **`cue cmd`
digest tool**, and **zot at Slice 1.5** on a two-address spike. What is frozen:
the `regctl` swap, Chainsaw-before-1.5, Flux pulled forward, Tekton bundles,
OpenBao pulled forward, Flagger. The SSOT slice order stands until the probes
replace prose with facts.

## Goals

- Land the tooling wins that are verified safe; freeze the rest.
- Every remaining claim is either checked against upstream docs in this doc or
  scheduled as a probe.
- Each step is a bisect-safe commit whose blast radius is enumerated.
- KISS, negative space, correctness over speed. "Re-sequencing five decisions
  around a tool whose guarantee you have not read is how a learning project
  acquires the one bug it cannot bisect" — the outside voice.

## Constraints

Unchanged from `pipeline-restructure.md`. OrbStack k8s `v1.35.6+orb1`,
**cri-dockerd** `docker://29.4.0`, arm64, single node.

---

## Part 1 — Tooling pass (land now)

Two tools. Honest LOC delta: `check-toolchain.sh` (43) + `gen-digests.sh` (67)
→ `mise.toml` + `digests_tool.cue` (~35). **~75 lines, not the 365 an earlier
draft claimed** (that number counted the `regctl` and Chainsaw swaps, both now
frozen).

### 1 — mise

```
- mise.toml + mise.lock (repo-scoped; .mise.local.toml gitignored)
- FIRST verify every tool has a real mise backend: cue, kubectl, jq, yq,
  shellcheck, bats are fine; apko, chainsaw, kubeconform, tkn need checking —
  fall back to `ubi:` / `http:` backends or keep those in docs/bootstrap-toolchain.md
- delete scripts/check-toolchain.sh
- docs/bootstrap-toolchain.md → "run: mise install" + the version table stays
  as the human-readable record (do not delete the prose — it is the SSOT the
  in-cluster apko lock is diffed against)
- bootstrap.sh: drop phase 0 (mise install replaces it)
- NEW: a bats test diffs mise.toml versions against
  bootstrap/pipeline-utils/apko.lock.json for the overlapping tools
  (cue, jq) — host/in-cluster skew is exactly the Slice 2 nondeterminism class
  (outside-voice finding 33)
```

### 2 — `cue cmd` digest tool

```
- add cue.mod/ (module.cue) — does not exist yet (outside-voice finding 35)
- digests_tool.cue (tool/file + encoding/yaml) generates digests.env + params.yaml
- SAME COMMIT, or the pre-commit hook goes red:
    .githooks/pre-commit step 2  (shells scripts/gen-digests.sh)
    scripts/test/gen-digests.bats
    docs/runbook.md "gen-digests.sh produces a diff" entry
- delete scripts/gen-digests.sh
- jq is NOT removed — it is still a hard `need` in build-pipeline-utils.sh and
  e2e.sh and in the apko package list (outside-voice finding 34). The tool file
  just stops the digest path from using it.
- pin `cue` hard in mise.toml — the tool/ API has moved across releases
```

`validate.sh` is **not** thinned (outside-voice finding 32: the whole-tree
`git ls-files` discovery is what makes the hard-coded-image grep a repo-wide
invariant; the pre-commit hook calls it with no args).

### Frozen — do NOT do in the pass

| Swap | Why frozen | Unfreezes when |
|---|---|---|
| **regctl replaces crane for assembly** | `regctl image mod` has no `--config-user`/`--config-workdir`; `--layer-add dir=` roots at `/` not `/app`; `--time "@epoch"` is invalid (`set=<RFC3339>`); `export \| docker load` format bridge unverified on `docker://29.4.0` | probe P1 + P2 (below). Even then: the ephemeral `crane registry serve` is only killable if regctl does BOTH append and config locally — confirm |
| **Chainsaw before Slice 1.5** | ~half the e2e assertions are host-Docker facts (image in the OrbStack store, pod `imageID` == `docker inspect`) — Chainsaw expresses those only as `script:` (bash in YAML). Doing it at parity with behaviour Slice 1.5 deletes is double work | after Slice 1.5, at parity with the kept `@sha256` behaviour |
| **Flux pulled to Slice 3** | `spec.verify` ≠ the verify PipelineRun (see Part 3); Slice 3 would land 5 controllers at once (Gall's Law, relocated) | probe P5 + a Slice-3 split design |
| **Tekton bundles (Slice 1.7)** | bundles resolver has no plain-HTTP option; the resolver pod (`tekton-pipelines-resolvers` ns) can't reach a `127.0.0.1` hostPort or a namespace-scoped-NetworkPolicy'd zot; needs zot TLS + a CA in the resolver deployment — reopens 2a-A | probe P4 |
| **OpenBao pulled to Slice 4** | Shamir unseal = manual key-share entry after every OrbStack restart (daily tax); an ESO-synced static Vault token is the same secret class the plan claims to remove | probe P6 (Chains + sigstore `hashivault://` against OpenBao + the auth mode) |
| **Flagger / Slice 8** | `provider: kubernetes` has no traffic telemetry → no metric to gate on; needs `cv_frontend` to export `/metrics`; Flagger + Flux fight over the Deployment | probe P7 + a `cv_frontend` metrics prereq decision |
| **Flux image-automation (G2)** | Setters can't write CUE; would target `params.yaml` (generated) and break the drift check; Flux can't open PRs | dropped — base-digest bumps stay reviewed commits (Rule 12), the right answer for a learning repo |

---

## Part 2 — zot at Slice 1.5 (verified-feasible with the corrections below)

zot is the one re-sequence that survives. It retires two debt items
(`docker.sock` mount, deploy-by-tag) and it is a single component. But the CEO
review's seed spec had errors — corrected here.

### Spike `1.5a` — TWO pass criteria (was one)

```
PASS requires BOTH:
  (a) kubelet pulls  127.0.0.1:5000/probe@sha256:<digest>  → pod Running ≤60s,
      `kubectl describe` shows no ErrImagePull
      (works because Docker's default insecure-registry CIDR is 127.0.0.0/8)
  (b) an in-cluster pod (different namespace) pushes to AND pulls from zot at
      the node-IP or ClusterIP address over plain HTTP
      (regctl --host <addr>,tls=disabled  or equivalent)
FAIL on either → document the two-address split + `orb config docker`
  insecure-registries fallback, revert the spike, take that path.
```

The **two-address rule** is a first-class runbook fact, like the existing DNS
finding: **kubelet pulls via `127.0.0.1:5000`; every in-cluster client
(`assemble`, and later Flux, the Tekton resolver) uses the node-IP/ClusterIP
address over plain HTTP.** Every client needs its own plain-HTTP config
(`regctl` host config, Flux `.spec.insecure: true`, …).

### Seed spec — corrected

```
manifests/zot/{deployment,service,pvc}.yaml
  - hostPort 127.0.0.1:5000  +  a normal Service on the ClusterIP
  - readinessProbe: GET /v2/
  - PVC 10Gi
  - namespace pod-security.kubernetes.io/enforce=PRIVILEGED   ← NOT baseline;
    baseline FORBIDS hostPort (outside-voice finding 6). Record in debt.md.
  NO NetworkPolicy in the 1.5 seed — a namespace-scoped one blocks the Tekton
    resolver and Flux (different namespaces). It moves to Slice 3 with the
    consumer set enumerated: cv-pipeline, tekton-pipelines-resolvers, flux-system
    (outside-voice finding 8).
bootstrap.sh: + phase "wait zot Available" + a df warning on the zot PVC
```

### Commit chain — Slice 1.5 (THREE commits for the swap, not two)

```
1.5a  spike (throwaway) — the two-criteria probe above
1.5b  manifests/zot/ (Deployment + Service + PVC, PSA privileged) ;
      bootstrap wait-gate + df warning ; kubeconform
1.5c  assemble ALSO pushes to zot (crane push to the ClusterIP addr, plain HTTP)
      — KEEPS docker-load + the tag ; image now exists in BOTH places ; GREEN
1.5d  deploy + smoke: image = <zot-clusteraddr>/cv@sha256:<digest> ;
      imagePullPolicy: IfNotPresent ; ADD runAsUser: 65532 explicitly to the
      pod specs (crane still sets image USER, but be explicit — outside-voice
      finding 1) ; flip the e2e assertions (5 of them + 2 teardown paths —
      outside-voice finding 14) ; e2e must `docker rmi` the digest before deploy
      OR use imagePullPolicy: Always for the assertion, so "pulled from zot" is
      actually exercised (outside-voice finding 9)
1.5e  drop the /var/run/docker.sock mount + the uid-0 assemble-and-load step +
      the docker-load from assemble  (now that nothing needs the local store)
      → debt.md: retire "docker.sock mount" + "deploy by tag"
      → debt.md: ADD "zot-on-hostPort is single-node only — redo the registry
        address at Slice 5 / any second node" (outside-voice finding 31)
      → runbook.md: "zot down + IfNotPresent → ImagePullBackOff on a fresh pod"
```

Assembly stays **crane** (ephemeral registry + `append` + `mutate -u 65532
-w /app`). No regctl.

### Slice renumber

- SSOT Slice 1.5 (per-stage SAs) → **Slice 1.6**.
- Everything from Slice 2 on: **unchanged from the SSOT**, except Slice 3 no
  longer stands up zot (it already exists) — Slice 3 keeps Trivy + CVE gate +
  SBOM + the NetworkPolicy (now with the enumerated consumer set).
- Slice 3 SBOM: push as a **plain OCI referrer** (`regctl artifact put` /
  `oras attach`) — `cosign attest --type spdxjson` needs a key that doesn't
  exist until Slice 4 (outside-voice finding 19; inherited bug in
  `pipeline-restructure.md:378`).

---

## Part 3 — What the probes must answer before the frozen slices re-plan

`probes/` — throwaway scripts, run against the live cluster, results into a
findings doc. Not committed.

| Probe | Question | Blocks |
|---|---|---|
| **P1** | `regctl image mod` on the pinned version: can it set user/workdir (any flag, `blob put` + `manifest put`)? does `--layer-add dir=` vs `tar=` root correctly? exact `--time` syntax? `--reproducible` behaviour? | the regctl swap; Slice 2 determinism payoff |
| **P2** | `regctl image export ocidir://… \| docker load` on `docker://29.4.0` — does the daemon accept OCI-layout tarballs? | the regctl swap |
| **P3** | (folded into spike `1.5a`) zot two-address reachability + plain-HTTP | Slice 1.5 |
| **P4** | Can the Tekton **bundles resolver** pull from a plain-HTTP zot at the ClusterIP addr? If not, what CA/TLS wiring does `tekton-pipelines-resolvers` need? | Slice 1.7 (bundles); the "inline scripts" idea |
| **P5** | `Flux OCIRepository.spec.verify` — exact scope: config artifact only, or can it gate the referenced image? does it touch attestations? what is the failure/retry behaviour and can it be bounded? | Flux pulled forward; the CM-1-A question |
| **P6** | Tekton Chains + sigstore `hashivault://` against **OpenBao** (a Vault fork) — does it work, and via K8s auth or a static token? | OpenBao pulled forward |
| **P7** | Flagger meshless (`provider: kubernetes`) — is there ANY metric signal without a mesh? does `cv_frontend` need `/metrics`? Flagger-vs-Flux Deployment ownership | Slice 8 (progressive delivery) |

---

## Confirmed decisions

### Held from the SSOT / prior reviews (NOT reversed)

| # | Decision | Status |
|---|---|---|
| CM-1-A | Slice 4 = build run + **separate** verify+deploy PipelineRun (`cosign verify` + `cosign verify-attestation` + `refSource` predicate assertion, gating deploy). Trigger on build-run success; the verify run re-fetches by name+UID, polls zot for the `.sig`/`.att` referrers with a **bounded** timeout, verifies itself. | **stands** — the CEO review's "Flux spec.verify replaces this" reversal is **withdrawn** (outside-voice findings 21–23) |
| 8c-A | assert `.sig` + `.att` referrers exist in zot within N seconds of the build run | **stands** — it lives in the verify PipelineRun, which C would have deleted |
| CM-2-A | Slice 4 signs with a K8s cosign key Secret; OpenBao is its **own later slice** | **stands** — the CEO review's "OpenBao → Slice 4 via ESO" is **frozen** behind probe P6 |
| 2a-A | zot TLS story: a plain openssl CA Secret, CA into consumers | **partially stands** — Slice 1.5 uses plain-HTTP two-address (verified feasible for kubelet + `assemble`); TLS + CA returns if probe P4 says the bundles resolver needs it |
| T6-A | GitOps (Flux + Timoni) at **Slice 7** | **stands** — the "Flux → Slice 3" reversal is **frozen** behind probe P5 + a Slice-3 split design |
| T5-A | flat kustomize / minimal config scaffolding through Slice 6; Timoni at 7 | **stands** — real `manifests/` only where zot/deploy needs them |

### New (this review, verified)

| # | Decision |
|---|---|
| Tooling pass | **mise + `cue cmd` only**. `validate.sh` not thinned. jq not removed. `cue.mod/` added. mise/apko drift bats test added. |
| zot | Slice 1.5, **two-address spike**, PSA **privileged**, NetworkPolicy **deferred to Slice 3** with enumerated consumers, 3-commit swap keeping docker-load green until 1.5d, explicit `runAsUser: 65532` in pod specs. |
| SBOM | Slice 3 = plain OCI referrer; `cosign attest` at Slice 4. |
| image-automation (G2) | **dropped** — base-digest bumps stay reviewed commits. |
| Chainsaw | **after** Slice 1.5, at `@sha256` parity. Still the right tool for the e2e/negative *scenarios*; just not now and not the "365 LOC" framing. |
| `pipeline-utils` ref | fix the tag→digest reference (`e2e.sh:31` etc. use `cv/pipeline-utils:slice1-arm64`, the `digests.cue` pin is decorative) while touching the image for mise (outside-voice finding 36). |

### Frozen behind probes (re-plan after P1–P7)

regctl-for-assembly, Flux-forward, Tekton-bundles, OpenBao-forward,
Flagger/Slice-8. Each gets its own review once its probe lands.

---

## Innovation-token ledger

Lands now: **mise** (dev-plane), **`cue cmd`** (already have `cue`), **zot** (was
Slice 3, now 1.5 — same component, earlier).

Frozen: regctl, Flux-forward, Flagger, OpenBao-forward, Tekton-bundles.

Dropped: kapp, Flux image-automation, `regctl`-replaces-`crane`, Chainsaw-now.

The SSOT's slice-by-slice token spend is **unchanged**. This proposal moves one
component (zot) and adds one dev tool (mise). That is the whole verified delta.

## What already exists (reused)

`digests.cue` (SSOT — `cue cmd` replaces the generator, not the schema; needs a
`cue.mod/`); apko + `build-pipeline-utils.sh` + **crane** (kept for assembly);
the per-run PVC; bats; `validate.sh` (unchanged); `.githooks/pre-commit`
(updated in the `cue cmd` commit). Tekton remote resolution is **NOT** currently
in use (`pipeline.yaml` uses `taskRef: {name:}`) — the SSOT's "git-resolved by
commit" is aspirational; introducing it is net-new work whenever bundles
unfreeze (outside-voice finding 11).

## NOT in scope

- The `regctl` assembly swap, Chainsaw-now, Flux-forward, Tekton-bundles,
  OpenBao-forward, Flagger — all frozen behind probes.
- Rewriting `pipeline-restructure.md` beyond the tooling-pass + Slice 1.5/1.6
  renumber.
- Any Slice 1.5+ implementation commit before the tooling pass + spike land.
- The infra plane (Crossplane / OpenTofu / k0s) — separate arc.

## Failure-modes registry (verified-scope only)

```
CODEPATH                          | FAILURE MODE                    | RESCUED?          | TEST?       | SEES?            | LOGGED?
----------------------------------|--------------------------------|-------------------|-------------|------------------|--------
cue cmd gen (pre-commit)          | cue.mod/ missing / API drift    | Y (hook red)      | gen-digests.bats | hook output  | Y
mise install                      | tool has no backend             | Y (mise errors)   | drift bats  | mise output      | Y
mise vs apko tool skew            | silent version drift            | Y (NEW drift bats)| the bats    | test failure     | Y
spike 1.5a                        | one of two addresses fails      | Y (two-criteria PASS/FAIL) | n/a (spike) | explicit FAIL | Y
1.5c assemble → zot push          | zot down mid-push               | Y (Rule 13 fail-loud + pipefail) | Chainsaw neg (later) | assemble red | Y
1.5d kubelet pull zot@sha256      | zot down, IfNotPresent cache hit hides it | N — mitigated: e2e docker-rmi's the digest first (finding 9) | e2e | ImagePullBackOff | Y
```

No RESCUED=N + TEST=N + SILENT row → **no critical gaps** in the verified scope.

---

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 1 | issues_open | HOLD_SCOPE → approach C → **scaled back after outside voice**; tooling pass reduced to mise + cue cmd; zot@1.5 kept with corrections; everything else frozen behind probes P1–P7; CM-1-A reversal withdrawn |
| Codex Review | `/codex review` | Independent 2nd opinion | 0 | — | — |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | issues_open | 19 decisions; **several invalidated by the outside voice** (regctl swap, G2, G3b) — re-run after the probes |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | — | n/a (infra) |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | — | — |

- **CODEX:** `codex exec` timed out twice with no output — stalls on this repo.
- **OUTSIDE VOICE (Opus subagent):** 36 findings, doc-cited. Invalidated 3 of 5 headline tool swaps + the central Flux `spec.verify` claim. Verdict: "the direction is right; neither review checked a single command." User adopted the 80/20 scale-back.
- **CROSS-MODEL:** the outside voice and both prior reviews AGREE on direction (fewer scripts, GitOps eventually, zot forward). They DISAGREE on specifics — the outside voice wins every specific because it cited upstream docs and the prior reviews had not run the tools.
- **VERDICT:** NOT cleared to implement. The verified subset (mise, `cue cmd`, zot@1.5-corrected) is ready for a focused `/plan-eng-review` and then implementation. The frozen subset needs probes P1–P7, then a fresh review per unfrozen slice.

**UNRESOLVED DECISIONS:**
- Probe P1–P7 outcomes — each frozen slice re-plans only after its probe lands
- Whether the tooling pass + zot@1.5-corrected merges into `pipeline-restructure.md` now, or waits for a confirming `/plan-eng-review`
- `cv_frontend` `/metrics` endpoint — a prerequisite decision for any future Flagger slice (like `/healthz` was for Slice 1)
