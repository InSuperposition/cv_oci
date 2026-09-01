# Accepted-compromise ledger

Known compromises accepted during planning, each with the trigger that should
prompt a revisit. Distinct from `TODOS.md` (new work). Reviewed at the start of
each slice.

| Compromise | Why accepted | Upgrade when | Target |
|---|---|---|---|
| Option A: the runtime image carries an in-process compiler (esbuild / oxc / lightningcss via `remix/node-tsx` + the asset server) | `remix@3` has no build step; its supported deploy model runs the asset server in production. CNB does not change this. | request-time bundling proves a determinism or security problem | Option C (snapshot assets to static) |
| CNB `buildpacks` task `prepare` step runs as root (uid 0) | it `chown`s `/layers`, `/tekton/home` and the source workspace to the builder uid; the upstream tektoncd/catalog task does this and there is no non-root variant | **Slice 1.7 code landed:** `stepTemplate.securityContext` runs every step uid 1000 PSA-restricted, the `chown` is deleted, `fetch` runs uid 1000, `cv-pipeline` labelled `enforce=restricted`, `bootstrap.sh` sets `set-security-context=true`. **Delete this row once `e2e.sh` + `negative.sh` + `repro.sh` pass green against a restricted `cv-pipeline`.** | live-verify pending |
| Runtime image is `heroku/heroku:24` — a full Ubuntu 24.04 base (shell, `apt`, `npm`, Node) | adopting a stock CNB builder means adopting its run image; `heroku` has no distroless variant, and a probe of `heroku/builder:24` + `-run-image=paketobuildpacks/run-noble-tiny` failed at export (`MANIFEST_INVALID`, tiny image missing `io.buildpacks.base.distro.*` labels). Weaker than the retired crane/apko distroless runtime. | a compatible distroless multi-arch run image exists, or a second cluster / real deploy target raises the stakes | custom run image with the required base-distro labels, or switch builders |
| CNB app image lives in plain-HTTP zot (no TLS, no auth) | the zot seed is unauthenticated by design; TLS on a solo single-node cluster protects nothing new | Slice 6 (authz) / any second node | Slice 6 → htpasswd + TLS; multi-node → real registry ingress |
| zot `NetworkPolicy` not applied | **wontfix on a single-node solo cluster** (eng review 2026-09-01) — no hostile tenant to isolate zot from, and every candidate policy risks breaking kubelet pulls, the throwaway `cv-e2e-*`/`cv-repro-*` test namespaces, and Flux. Recorded as a non-goal in `docs/designs/buildpacks-pivot.md`. | any second node, or any multi-tenant scenario | a consumer-scoped policy, its own slice, when a real trust boundary exists |
| No build cache (`SKIP_RESTORE=true`) | 1-dep app; a cache is another determinism variable and a zot round-trip per build | build time bites as `cv_frontend` deps grow | zot `CACHE_IMAGE` (TODOS.md: npm cache) |
| Registry-trust bootstrap is per-platform node config (`k8s.expose_services` + `docker.json` insecure-registries) | Kubernetes treats registry trust as node/runtime config; unavoidable | — | documented per-platform step in `docs/runbook.md`, not "fixed" |
| Flat kustomize bases as config tooling | the Timoni end state is not proven yet; minimal scaffolding avoids sunk work | Slice 7 lands | Slice 7 → Timoni modules |
| Slice 4 signs with a cosign key in a Kubernetes Secret | dev-mode OpenBao is strictly worse (no persistence, restart loses the key); persistent OpenBao is its own arc | you want the KMS / transit-signing lesson | OpenBao slice |
| `npm ci` runs cold every build | see "no build cache" above | — | — |
| Rule 4 portability is asserted, not tested | no second cluster exists yet | before Slice 5 | TODOS.md: portability kind-CI |
| `validate.sh` fetches the Kubernetes core schema set from a version-pinned URL, not a vendored copy | the full standalone set is hundreds of files; a pinned URL is reproducible enough for a local learning repo | validation needs to run offline / in air-gapped CI | vendor `schemas/k8s/v1.31.0/` |

## Resolved

| Was | Finding | Fix |
|---|---|---|
| "CNB builds are not byte-reproducible; the lifecycle does not honour `SOURCE_DATE_EPOCH`" | Not the lifecycle. Two independent builds of one fixture SHA already agreed on the SBOM layer and 10 of 12 other layer diffIDs, gzip-compressed digests included (`created` is pinned to `1980-01-01T00:00:01Z`). The **only** drift was the app layer, caused by our own `fetch` step leaving `.git/` (— `.git/index` stat cache, `.git/logs/HEAD` reflog timestamps —) in the source tree for the buildpack to copy in. | `pipeline/pipeline.yaml` `fetch` step `rm -rf .git` after the SHA is captured. Builds are now byte-for-byte reproducible (identical outer image digest). Guarded by `scripts/test/repro.sh` (Slice 2). |
