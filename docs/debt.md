# Accepted-compromise ledger

Known compromises accepted during planning, each with the trigger that should
prompt a revisit. Distinct from `TODOS.md` (new work). Reviewed at the start of
each slice.

| Compromise | Why accepted | Upgrade when | Target |
|---|---|---|---|
| Option A: the runtime image carries an in-process compiler (esbuild via `remix/node-tsx` + the asset server) | `remix@3` has no build step; its supported deploy model runs the asset server in production. Correctness-first on a moving beta. | request-time bundling proves a determinism or security problem | Slice 2 → Option C (snapshot assets to static) |
| Flat kustomize bases as config tooling | the Timoni end state is not proven yet; minimal scaffolding avoids sunk work | Slice 7 lands | Slice 7 → Timoni modules |
| Slice 4 signs with a cosign key in a Kubernetes Secret | dev-mode OpenBao is strictly worse (no persistence, restart loses the key); persistent OpenBao is its own arc | you want the KMS / transit-signing lesson | OpenBao slice |
| Plain openssl CA Secret for zot's cert, manual rotation | Rule 15 — one internal cert does not justify cert-manager | cert automation is actually needed (multi-service TLS, Flux) | Slice 7 revisit |
| `npm ci` runs cold every build (no cache) | 1-dep app; a cache is another determinism variable | build time bites as `cv_frontend` deps grow | TODOS.md: npm cache |
| Rule 4 portability is asserted, not tested | no second cluster exists yet | before Slice 5 | TODOS.md: portability kind-CI |
| Registry-trust bootstrap is per-platform node config | Kubernetes treats registry trust as node/runtime config; unavoidable | — | documented caveat in the design doc, not "fixed" |
| `pipeline-utils` image is arm64-only | OrbStack is the only cluster; multi-arch build is Slice 5's subject | the portability kind-CI or Slice 5 needs it on amd64 | TODOS.md: multi-arch pipeline-utils |
| zot unauthenticated for Slices 1-5 (NetworkPolicy only) | full authz is real work; deploy-by-digest limits blast radius on a solo cluster | Slice 6 | Slice 6 → htpasswd / full authz |
| `validate.sh` fetches the Kubernetes core schema set from a version-pinned URL, not a vendored copy | the full standalone set is hundreds of files; a pinned URL is reproducible enough for a local learning repo | validation needs to run offline / in air-gapped CI | vendor `schemas/k8s/v1.31.0/` |
| Slice 1 `assemble` mounts `/var/run/docker.sock` and `docker load`s the built image into the OrbStack store instead of pushing to a registry | OrbStack's Docker daemon can't resolve `*.svc` and needs an `insecure-registries` edit for any in-cluster registry; standing that up buys the tracer bullet nothing | Slice 3 (the CVE gate needs a running registry) | Slice 3 → `crane push` to in-cluster zot, drop the socket mount |
| Slice 1 deploys by an immutable tag (`cv:git-<full-sha>`), not `@sha256:` | OrbStack's `docker load` records no repo digest, so `imagePullPolicy: Never` + `image: cv@sha256:...` gives `ErrImageNeverPull` | Slice 3 (a real registry restores digest-ref pull) | Slice 3 → `image: zot/cv@sha256:...` |
| No in-cluster registry, CA, or NetworkPolicy in Slice 1 | see above — deferred to where it is load-bearing | Slice 3 | Slice 3 → zot Deployment + `orb config docker` insecure-registries + NetworkPolicy |
| CNB `buildpacks` task `prepare` step runs as root (uid 0) | it `chown`s `/layers`, `/tekton/home` and the source workspace to the builder uid; the upstream tektoncd/catalog task does this and there is no non-root variant | a rootless CNB prepare path exists, or PSA `restricted` is enforced on `cv-pipeline` | vendor a non-root prepare, or pre-own the workspaces via `fsGroup` + an init container |
| CNB app image is deployed from plain-HTTP zot (no TLS, no auth) | Slice 1.5 zot seed is unauthenticated by design; TLS on a solo single-node cluster protects nothing new | Slice 6 (authz) / any second node | Slice 6 → htpasswd + TLS; multi-node → real registry ingress |
| zot `NetworkPolicy` not applied in the CNB seed | a namespace-scoped policy blocks the Tekton resolver + future Flux (different namespaces); the consumer set is not enumerated yet | Slice 3 | Slice 3 → NetworkPolicy with consumers: `cv-pipeline`, `tekton-pipelines-resolvers`, `flux-system` |
| CNB builds are not byte-reproducible (two builds of one SHA differ) | the lifecycle does not honour `SOURCE_DATE_EPOCH` / normalise layer order by default | the determinism lesson (Slice 2) | Slice 2 → `SOURCE_DATE_EPOCH` + layer normalisation; assert equal SBOM package set + app-layer content hash, not raw digest |
