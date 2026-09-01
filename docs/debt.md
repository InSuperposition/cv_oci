# Accepted-compromise ledger

Known compromises accepted during planning, each with the trigger that should
prompt a revisit. Distinct from `TODOS.md` (new work). Reviewed at the start of
each slice.

| Compromise | Why accepted | Upgrade when | Target |
|---|---|---|---|
| Option A: the runtime image carries an in-process compiler (esbuild / oxc / lightningcss via `remix/node-tsx` + the asset server) | `remix@3` has no build step; its supported deploy model runs the asset server in production. CNB does not change this. | request-time bundling proves a determinism or security problem | Option C (snapshot assets to static) |
| CNB `buildpacks` task `prepare` step runs as root (uid 0) | it `chown`s `/layers`, `/tekton/home` and the source workspace to the builder uid; the upstream tektoncd/catalog task does this and there is no non-root variant | a rootless CNB prepare path exists, or PSA `restricted` is enforced on `cv-pipeline` | vendor a non-root prepare, or pre-own the workspaces via `fsGroup` + an init container |
| CNB app image lives in plain-HTTP zot (no TLS, no auth) | the zot seed is unauthenticated by design; TLS on a solo single-node cluster protects nothing new | Slice 6 (authz) / any second node | Slice 6 → htpasswd + TLS; multi-node → real registry ingress |
| zot `NetworkPolicy` not applied in the seed | a namespace-scoped policy blocks the Tekton resolver + future Flux (different namespaces); the consumer set is not enumerated yet | Slice 3 | Slice 3 → NetworkPolicy with consumers: `cv-pipeline`, `tekton-pipelines-resolvers`, `flux-system` |
| CNB builds are not byte-reproducible (two builds of one SHA differ) | the lifecycle does not honour `SOURCE_DATE_EPOCH` / normalise layer order by default | the determinism lesson (Slice 2) | Slice 2 → `SOURCE_DATE_EPOCH` + layer normalisation; assert equal SBOM package set + app-layer content hash, not raw digest |
| No build cache (`SKIP_RESTORE=true`) | 1-dep app; a cache is another determinism variable and a zot round-trip per build | build time bites as `cv_frontend` deps grow | zot `CACHE_IMAGE` (TODOS.md: npm cache) |
| Registry-trust bootstrap is per-platform node config (`k8s.expose_services` + `docker.json` insecure-registries) | Kubernetes treats registry trust as node/runtime config; unavoidable | — | documented per-platform step in `docs/runbook.md`, not "fixed" |
| Flat kustomize bases as config tooling | the Timoni end state is not proven yet; minimal scaffolding avoids sunk work | Slice 7 lands | Slice 7 → Timoni modules |
| Slice 4 signs with a cosign key in a Kubernetes Secret | dev-mode OpenBao is strictly worse (no persistence, restart loses the key); persistent OpenBao is its own arc | you want the KMS / transit-signing lesson | OpenBao slice |
| `npm ci` runs cold every build | see "no build cache" above | — | — |
| Rule 4 portability is asserted, not tested | no second cluster exists yet | before Slice 5 | TODOS.md: portability kind-CI |
| `validate.sh` fetches the Kubernetes core schema set from a version-pinned URL, not a vendored copy | the full standalone set is hundreds of files; a pinned URL is reproducible enough for a local learning repo | validation needs to run offline / in air-gapped CI | vendor `schemas/k8s/v1.31.0/` |
