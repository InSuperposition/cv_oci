# "The Assignment" — what the cv_frontend runtime actually needs

Run 2026-08-30 against `cv_frontend` @ `0bbc684` (`remix@3.0.0-beta.10`, Node
24.20). Method: `rsync` the source (no `node_modules`) to a scratch dir,
`npm ci --omit=dev`, run `NODE_ENV=production node --import remix/node-tsx
server.ts`, hit `/`, `/healthz`, and asset URLs, watch for runtime disk writes.

## Answers

### Does a compiler run at request time?

**Effectively no.** `app/assets.ts` has top-level `await
assetServer.getHref(entry)` + `getPreloads(entry)`. `getPreloads` walks and
compiles the entire client module graph (~45 modules: the entry, the interactive
`prompt-button`, and all of `@remix-run/ui`) **at server startup**. By the time
the server is listening the client surface is compiled and cached in memory.

Measured: startup ~103ms; first `GET /` 15ms; first `GET /assets/...` 2.6ms; a
"cold" `prompt-button.tsx` request 2.8ms. No cold-bundle penalty because this
app has no client module outside the entry graph.

Caveat: a route that *lazily* imported a client module not reachable from the
entry would compile that on demand. This app has none. If one is added, the
warm-on-startup step (below) must be extended or Option C brought forward.

### What runs the compile?

Remix 3 uses **oxc** (Rust), not just esbuild:
- `@remix-run/node-tsx@0.1.1` → `oxc-transform` — the runtime `.ts`/`.tsx` loader
  (`--import remix/node-tsx`).
- `remix/assets` (`@remix-run/assets`) → bundles browser modules; `minify: true`
  in prod runs `oxc-minify`; module resolution via `@oxc-resolver`.
- `esbuild@0.27.7` is also present (via `remix > @remix-run/test > esbuild`) and
  `lightningcss` (CSS). All have platform-scoped native binaries.

### Does it write to disk at runtime?

**No.** After startup, serving requests created/modified nothing in the tree.
The asset cache is in memory. `readOnlyRootFilesystem: true` is viable (with a
writable `/tmp` emptyDir if Node ever needs one — none observed).

### What is the release tree?

Files the runtime needs, from a prod-only install:

```
server.ts                  entrypoint (run via node --import remix/node-tsx)
tsconfig.json              read by node-tsx's get-tsconfig at load
app/                       all .ts/.tsx — loaded + transformed at runtime
public/                    static files (favicon.svg), served by staticFiles mw
package.json               remix resolves subpath exports against it
package-lock.json          reference (not strictly needed at runtime)
node_modules/              PRODUCTION deps only, ~50MB, 88 packages
```

**Not** in the release tree: `hmr.ts` (only `npm run hmr`, dev), `.agents/`,
`AGENTS.md`, `README.md`, `.gitignore`, `devDependencies` (`typescript`,
`@types/node` — confirmed absent after `--omit=dev`).

### Platform trap

Prod `node_modules` contains **platform-scoped native binaries**: `esbuild`
(`@esbuild/<os>-<arch>`), `lightningcss` (`lightningcss-<os>-<arch>`),
`@oxc-resolver` / `@oxc-transform` / `@oxc-minify` / `@oxc-parser`
(`*/binding-<os>-<arch>`). The scratch run installed `darwin-arm64` variants.

**The `build` Task MUST run `npm ci --omit=dev` on a `linux/arm64` node** (or in
a `linux/arm64` container). Copying a host `node_modules` into the image would
ship macOS binaries. npm's `optionalDependencies` + `os`/`cpu` fields fetch the
right ones automatically when `npm ci` runs on the target.

## What this means for the `build` and `assemble` Tasks

- `build` (arm64): `git-clone cv_frontend@APP_SHA` → `npm ci --omit=dev`
  (on-node, linux/arm64) → `npm audit signatures` → `npm run typecheck` (needs
  devDeps — install a second time with dev, or run typecheck before pruning) →
  `npm test` → copy `server.ts tsconfig.json app/ public/ package.json
  package-lock.json node_modules/` into the release tree → `assert-release-tree`.
- `assemble`: `crane append` the release tree onto pinned
  `gcr.io/distroless/nodejs24-debian12@sha256:…`; set `USER nonroot`,
  `WORKDIR /app`, `ENV PORT`, entrypoint `node`, CMD
  `["--import","remix/node-tsx","server.ts"]`.
- `cv_frontend` `app/assets.ts` needs a prod branch: `watch: false`,
  `fingerprint: { buildId: process.env.APP_SHA }`. That is a `cv_frontend`
  commit (bumps the pinned SHA), bundled with the `/healthz` work.
- **Warm-on-startup is largely already there** via `assets.ts`'s top-level
  `getPreloads`. Slice 1's readiness gate (6d-A) just needs to wait for that
  module's import to finish before reporting ready — which, since it's a
  top-level await in the import graph, it already does. The readiness endpoint
  (`/healthz`) is only reachable after `server.ts` finishes importing, so it is
  warm by construction.

## typecheck ordering note

`npm run typecheck` = `tsc --noEmit`, which needs `typescript` (a devDep). Either
run typecheck in a full `npm ci` step *before* the `--omit=dev` prune, or run it
in a separate throwaway install. Do not add `typescript` to the release tree.
