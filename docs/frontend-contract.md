# cv_frontend contract

Everything the `cv_oci` pipeline assumes about `github.com/InSuperposition/cv_frontend`.
The `resolve` Task asserts the **paths** section against the checked-out
`APP_SHA` and fails loud if anything is missing (finding 1c-A). Bump this doc in
the same commit that bumps the pinned `APP_SHA` when it changes.

Verified against `cv_frontend` @ `0bbc684` on 2026-08-30. See
`docs/assignment-findings.md` for the runtime investigation behind these.

## Repo identity

- Remote: `https://github.com/InSuperposition/cv_frontend`
- `app_revision` is a **full 40-hex commit SHA** (branches/tags are resolved to
  one before build — `resolve` Task).
- Each `cv_oci` commit pins a known-good `cv_frontend` fixture SHA in
  `digests.cue` (`frontendFixture`) so acceptance is meaningful at any checkout
  (finding codex #13). _Added when the fixture is chosen in Slice 1._

## Paths that MUST exist at APP_SHA (asserted by `resolve`)

```
server.ts
tsconfig.json
package.json
package-lock.json
app/
app/router.ts
app/routes.ts
app/assets.ts
public/
```

## package.json assumptions

- `"type": "module"` (ESM).
- `engines.node` satisfied by the runtime base (`nodejs24` → Node 24.x).
- `scripts.start` is `NODE_ENV=production node --import remix/node-tsx server.ts`
  — the pipeline uses this exact shape as the image CMD, it does not call
  `npm start`.
- `scripts.test` is `NODE_ENV=test node --import remix/node-tsx --test` — the
  `build` Task runs `npm test`; it must exercise real assertions (a `/healthz`
  + `/` router test is added in Slice 1 prep).
- `scripts.typecheck` is `tsc --noEmit` — needs the `typescript` devDep; run it
  from a full install, before the `--omit=dev` prune.
- Sole runtime dependency: `remix` (a beta — pinned exactly by the lockfile).
- `devDependencies` (`typescript`, `@types/node`) are NOT in the release tree.

## Runtime shape

- Entrypoint: `node --import remix/node-tsx server.ts`. `@remix-run/node-tsx` is
  the runtime TS loader (oxc-based); it is a prod dep of `remix`.
- `server.ts` reads `process.env.PORT` (default 44100). The pipeline sets `PORT`.
- The client asset graph is compiled at **startup** (top-level `await` in
  `app/assets.ts`), not per request. `/healthz` and `/` are only reachable after
  that import completes, so they are warm by construction.
- No runtime disk writes → `readOnlyRootFilesystem: true` is safe.
- Prod `node_modules` carries platform-scoped native binaries (esbuild,
  lightningcss, oxc-*). **`npm ci --omit=dev` runs on a `linux/arm64` node**, not
  copied from a build host of another arch.

## Routes

| Route | Purpose | Added |
|---|---|---|
| `GET /` | the app (SSR) | scaffold |
| `GET /assets/*path` | on-demand-compiled browser modules | scaffold |
| `GET /healthz` | liveness — 200 `text/plain`, no SSR | Slice 1 prep |

The smoke + deploy probes hit `GET /healthz` and expect `200`.

## Production `assets.ts` requirement

`app/assets.ts` must branch on `NODE_ENV === 'production'`:
`watch: false`, `fingerprint: { buildId: <APP_SHA> }`. This is the Option A
config (design doc); Slice 2 evaluates replacing it with a static asset snapshot
(Option C). Change lands in the same `cv_frontend` commit as `/healthz`.
