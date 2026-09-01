# Gate zero — arm64 CNB build probe

Decides Approach A (stock builder + Tekton `buildpacks` task) vs Approach C
(hand-rolled `/cnb/lifecycle/*` Task). See `docs/designs/buildpacks-pivot.md`.

## Result: PASS (2026-09-01)

`heroku/builder:24` (arm64) builds `cv_frontend` end to end on the OrbStack arm64
node via the vendored Tekton `buildpacks` 0.6 task, and the image runs and serves
traffic. **Proceed with Approach A.**

## What ran

Throwaway namespace `cv-gate-zero`, deleted after. Manifests were not committed
(scratchpad only). The vendored task is `tasks/buildpacks.yaml` (lands in
Commit 1a).

```
Pipeline: fetch (alpine/git clone cv_frontend@cb333ee) -> build (buildpacks 0.6)
Builder:  docker.io/heroku/builder:24@sha256:e74d36e0e70f9b588f62483bef73a51809c1f51f04103dbb323293261bfc43aa  (arm64 child)
Run image: docker.io/heroku/heroku:24  (arm64)
Registry: in-cluster registry:2, plain HTTP, CNB_INSECURE_REGISTRIES
Node:     kubernetes.io/arch=arm64  (native, no QEMU)
SKIP_RESTORE=true, no cache image, CNB_PLATFORM_API=0.9
```

## Assertions

| Check | Result |
|---|---|
| `/cnb/lifecycle/creator` exits 0 on arm64 | PASS |
| `heroku/nodejs` detects, runs `npm ci` from the lockfile (92 packages) | PASS |
| No `npm run build` script handled gracefully ("No build scripts found") | PASS |
| `npm prune` removes dev deps | PASS |
| default `web` process = `npm start` | PASS |
| image exported to the plain-HTTP in-cluster registry | PASS — `CNB_INSECURE_REGISTRIES` honored by lifecycle 0.21.18 |
| SBOM emitted | PASS — `/layers/sbom/launch/sbom.legacy.json` (Slice 3 confirms Syft/SPDX/CycloneDX) |
| image runs: `NODE_ENV=production node --import remix/node-tsx server.ts` | PASS |
| `GET /healthz` -> 200 `ok` | PASS |
| `GET /` -> 200, 35658 bytes (SSR + request-time asset compile) | PASS |
| `optionalDependencies` arm64 native binaries survive the launch-layer prune | PASS — `@esbuild/linux-arm64`, `@oxc-{parser,transform,minify,resolver,project}`, `lightningcss-linux-arm64-gnu` all present |

Image entrypoint `/cnb/process/web`, WorkingDir `/workspace/source`, user `heroku`.

## Known gaps (not gate-zero blockers — Commit 1a / later)

- **Deploy-by-digest from an in-cluster plain-HTTP registry.** OrbStack's kubelet
  refuses the plain-HTTP pull (`http: server gave HTTP response to HTTPS
  client`). This is the documented two-address / `orb config docker`
  insecure-registries problem (learning `orbstack-hostport-two-address`). The
  image was verified by `crane pull` + local `docker run` on the arm64 Mac
  instead. Commit 1a wires the real zot seed + the per-platform node trust step.
- **Reproducibility.** Two builds of `cb333ee` produced different image digests
  (`714ab0c2…` vs `b7a11fe3…`) — expected, CNB is not byte-reproducible without
  `SOURCE_DATE_EPOCH` + layer normalization. Slice 2 (determinism) owns this.
- **`tekton.dev/platforms: linux/amd64`** on the vendored task is advisory; the
  arm64 run succeeded regardless (only step images are `bash:5.1.4` (multi-arch)
  + the builder).
- **`prepare` step runs as root** (chowns `/layers`, `/tekton/home`, the source
  workspace). The one privileged bit; `debt.md` records it in Commit 1a. No PSA
  is enforced on the OrbStack namespaces, so it scheduled without a `privileged`
  label.

## Builder decision

`heroku/builder:24`, not Paketo. Every `paketobuildpacks/builder-*` on Docker
Hub is amd64-only (probed 2026-09-01); Heroku's is genuinely multi-arch. Heroku's
Node support is the monolithic `heroku/nodejs` buildpack (detect + install +
launch in one) rather than Paketo's `node-engine` / `npm-install` / `npm-start`
decomposition. For cv_oci that is fine. It matters for the deferred `cv_packs`
suite (TODOS.md).
