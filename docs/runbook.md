# Runbook

One entry per failure mode, added by the slice that introduces it. Format:
**symptom → likely cause → check → fix**.

---

## Slice 0

### `scripts/validate.sh` fails on a file you think is valid

- **Likely cause:** the file's `apiVersion`/`kind` has no pinned schema under
  `schemas/`, or kubeconform's schema-location order is wrong.
- **Check:** `scripts/validate.sh -v` (verbose) prints which schema it resolved
  per file. `ls schemas/` for the CRD in question.
- **Fix:** add the pinned CRD schema to `schemas/` (record its source + version in
  `docs/bootstrap-toolchain.md`), or if the file genuinely isn't a Kubernetes
  manifest, add it to the validator's skip list.

### `scripts/gen-digests.sh` produces a diff on a clean tree

- **Likely cause:** someone hand-edited `digests.env` or `params.yaml` instead of
  `digests.cue`; or the `cue` binary version drifted.
- **Check:** `cue version` matches the pin in `docs/bootstrap-toolchain.md`.
  `git diff digests.env params.yaml`.
- **Fix:** edit `digests.cue`, re-run `scripts/gen-digests.sh`, commit all three.
  The generated files are outputs — never edit them directly.

### Pre-commit hook blocks a commit

- **Likely cause:** shellcheck finding, a failing bats test, or `validate.sh`.
- **Check:** the hook prints which step failed. Re-run it manually:
  `.githooks/pre-commit`.
- **Fix:** address the finding. `git commit --no-verify` only for a genuine
  emergency, and fix it in the next commit.

### OrbStack registry trust — the two per-platform node steps

Verified 2026-09-01 on OrbStack k8s `v1.35.6+orb1`. The `cv` Deployment pulls
its image from the in-cluster zot **by digest**; that needs two one-time host
changes:

```
orb config set k8s.expose_services true      # then a full: orb stop / restart
# edit ~/.orbstack/config/docker.json:
{"insecure-registries":["zot.cv-pipeline.svc.cluster.local:5000"]}
orb restart docker                            # ~30s, restarts the k8s cluster too
```

With both, the OrbStack Docker daemon (the kubelet's puller) resolves and pulls
plain-HTTP from `zot.cv-pipeline.svc.cluster.local:5000`. OrbStack routes that
name to **both** the in-cluster network and the Mac daemon, so **one address
serves push and pull** — no two-address split, no hostPort.

Gotchas found while wiring this:

- A Pod `hostPort` on `127.0.0.1` does NOT work on OrbStack — the VM loopback is
  forwarded to the Mac loopback. And `127.0.0.1:5000` on the Mac is macOS
  AirPlay Receiver (`Server: AirTunes`, returns 403).
- Without `k8s.expose_services: true` the daemon can't resolve `*.svc` (it uses
  OrbStack DNS `0.250.250.200`).
- These steps are per-platform node config. A portable cluster substitutes its
  own registry ingress + trust config. `bootstrap.sh` phase 4 prints the two
  commands but does not run them (host config).

## The pipeline

### A chainsaw acceptance test fails

The suite lives in `tests/` (Kyverno Chainsaw, not the forensics tool of the
same name — see `docs/bootstrap-toolchain.md`). Each test runs the real
`cv-build` Pipeline in its own ephemeral PSA-`restricted` namespace.

- **Always pass `--config tests/.chainsaw.yaml`.** It is not auto-discovered
  (not even for `chainsaw test tests/`). Without it chainsaw uses defaults —
  `ExecTimeout 5s` — and every pipeline-wait step dies with `signal: killed`
  after ~5s. Full run: `chainsaw test --config tests/.chainsaw.yaml tests/`.
- **Run one test:** `chainsaw test --config tests/.chainsaw.yaml tests/pipeline-acceptance/`.
- **Keep the namespace on failure:** add `--skip-delete`.
  Then read the failing PipelineRun: `tkn -n <ns> pipelinerun logs -l
  cv-oci/acceptance-test=<test-name> --all`. Each test's `catch` block already
  dumps this on failure.
- **`build-is-reproducible`** builds the fixture SHA twice (the test's own
  namespace + a sibling `<ns>-b`) and asserts the two builds' app-layer and
  SBOM-layer content hashes agree. A FAIL on the app-layer check means something
  run-specific leaked into `/workspace/source` — check `fetch` still does
  `rm -rf .git` (`docs/debt.md` Resolved).
- **Common causes:** the OrbStack node-trust steps above are not done (the `cv`
  pod `ErrImagePull`s or gets `http: server gave HTTP response to HTTPS
  client`); cluster DNS blip in a Task pod (retry the run); Service-endpoint lag
  (smoke/deploy retry `/healthz` 10x — a persistent failure means the image
  genuinely doesn't serve); zot PVC full; Chains signing not finished
  (`pipeline-acceptance` waits up to 5m for `chains.tekton.dev/signed=true`).
- **Cleanup after `--skip-delete`:** `kubectl delete ns <ns> <ns>-b`;
  `crane delete --insecure zot.cv-pipeline.svc.cluster.local:5000/<ns>:git-<sha>`
  (the zot image has no shell — `kubectl exec -- rm` does not work).

### A PipelineRun is stuck / a stale `cv` Deployment is running

- **Rollback:** `kubectl -n cv-pipeline rollout undo deploy/cv`, or
  `kubectl -n cv-pipeline set image deploy/cv app=$(kubectl -n cv-pipeline get
  cm cv-deploy-state -o jsonpath='{.data.previous}')`. `cv-deploy-state.data`
  records `current_image`, `current_digest`, and `previous` (a `<zot>@sha256`
  ref); `kubectl rollout history deploy/cv` is the fuller trail.

### `cue vet digests.cue` fails with a constraint error

- **Likely cause:** a digest value is not `sha256:` + 64 hex chars (a tag slipped
  in, or a truncated digest).
- **Check:** the error names the field.
- **Fix:** put the full `sha256:...` digest in. Get it with
  `crane digest <ref>` (add `--platform linux/arm64` for a multi-arch image —
  the builder + run image are pinned by their arm64 CHILD digest).

### `cv` pod: `container has runAsNonRoot and image has non-numeric user`

- **Cause:** the Heroku/CNB launch user is the name `heroku`, not a uid. A pod
  with `runAsNonRoot: true` and no `runAsUser` can't verify it.
- **Fix:** the pipeline's smoke/deploy specs set `runAsUser: 1000` explicitly
  (`CNB_USER_ID` for the Heroku and Paketo stacks). Any hand-rolled Deployment
  of a CNB image needs the same.

### CNB build: two runs of one SHA give different image digests

- Since Slice 2 the build **is** byte-reproducible — two runs of one fixture
  SHA produce the identical outer image digest (`tests/build-is-reproducible`
  asserts it). If they diverge, the usual cause is the `fetch` step leaving
  `.git/` in the tree (its `rm -rf .git` regressed): `.git/index` and
  `.git/logs/HEAD` carry wall-clock data the buildpack copies into the app
  layer. The test also checks the per-CNB-layer content hashes from the
  `io.buildpacks.lifecycle.metadata` label, which localise the drift.

### Inspecting the CVE verdict + SBOM of a build (Slice 3)

The `scan` task records its work on the shared workspace (ephemeral) and as
PipelineRun results:

```
kubectl -n <ns> get pipelinerun <prn> -o jsonpath='{.status.results}' | jq
#   cve-verdict     pass | fail-critical
#   cve-db-digest   the ghcr.io/aquasecurity/trivy-db digest the verdict is against
#   sbom-components CycloneDX component count
```

To re-derive them from an image already in zot (host `trivy` + `crane`):

```
REF=zot.cv-pipeline.svc.cluster.local:5000/cv@sha256:<digest>
crane pull --insecure "$REF" /tmp/img.tar
trivy image --input /tmp/img.tar --severity CRITICAL --ignore-unfixed \
  --db-repository ghcr.io/aquasecurity/trivy-db@<pinned> --exit-code 1   # CVE gate
trivy image --input /tmp/img.tar --format cyclonedx | jq '.components | length'  # SBOM
```

The verdict is reproducible: the same `(image digest, DB digest)` pair always
gives the same answer, independent of when you run it.

### zot TLS (Slice 4) — cert not ready / pods can't pull

- `bootstrap.sh` waits on `certificate/cv-oci-ca` then `certificate/zot-tls`. If
  it hangs there: `kubectl -n cert-manager describe certificate cv-oci-ca` and
  `kubectl -n cv-pipeline describe certificate zot-tls` — usually the
  cert-manager webhook is not up yet (`kubectl -n cert-manager get pods`).
- zot serves HTTPS on `:5000`. `curl -k https://zot.cv-pipeline.svc.cluster.local:5000/v2/`
  from a debug pod, or `openssl s_client -connect zot.cv-pipeline.svc.cluster.local:5000`.
- Pipeline steps trust zot via `ca.crt` from the `zot-tls` Secret (mounted, YAML
  anchor). The Chains controller trusts it via the `cv-oci-ca-bundle` Secret
  (`manifests/chains/ca-cert.yaml`). The kubelet needs **no** change — the
  daemon `insecure-registries` entry already means "accept an unverified cert".
- Rotate the CA: `kubectl -n cert-manager delete secret cv-oci-ca` and let
  cert-manager reissue; every leaf reissues from the new CA within `renewBefore`.
  Consumers pick up the new `ca.crt` on the next pod restart.

### heroku/builder:24 emits no SBOM of its own

- The `create` step's launch SBOM layer is a 5-byte `null` (`bom_len: 0`,
  `sbom: none` in `io.buildpacks.build.metadata`). The `scan` step authors a
  CycloneDX SBOM with `trivy image --format cyclonedx` instead — scan-time
  provenance, not build-time. `docs/debt.md` carries the caveat.

## Slice 5a

### `kubectl apply -f manifests/rbac.yaml` fails: "cannot change roleRef"

- **Symptom:** on an already-bootstrapped cluster, applying the Slice 5a
  `manifests/rbac.yaml` errors on `cv-smoke-rolebinding` / `cv-deploy-rolebinding`
  with `roleRef: Invalid value: ... cannot change roleRef`.
- **Likely cause:** Slice 5a promoted `cv-smoke-role` / `cv-deploy-role` from
  namespaced `Role` to `ClusterRole`; the existing RoleBindings still point at
  `kind: Role`. `roleRef` is immutable — `apply` cannot patch it.
- **Fix (one-time migration):**
  ```
  kubectl -n cv-pipeline delete rolebinding cv-smoke-rolebinding cv-deploy-rolebinding
  kubectl apply -f manifests/rbac.yaml                       # recreates them -> ClusterRole
  kubectl -n cv-pipeline delete role cv-smoke-role cv-deploy-role   # old namespaced Roles
  ```
  A fresh `bootstrap.sh` run on an empty cluster has no conflict.

### `fetch` fails: `Could not resolve host: github.com (Timeout while contacting DNS servers)`

- **Symptom:** the `fetch` step (or a standalone `alpine/git` pod) fails
  intermittently on DNS. `pipeline-acceptance` / `-pre-healthz` /
  `build-is-reproducible` die at `fetch` or `build`. `pipeline-rejects-bad-ref`
  still "passes" because it expects `fetch` to fail anyway.
- **Root cause (investigated 2026-09-02):** NOT cv_oci. Host-side DNS was
  intermittently failing — `curl -4 https://github.com` from the Mac itself
  returned "Could not resolve host" then worked seconds later. The host ran ~10
  VPN/tunnel interfaces (`utun0`-`utun8`, `ipsec0`) with default routes and
  MTUs 1000-2000, plus IPv6-primary resolvers with shaky IPv6 (`ping6
  <resolver>` → "No route to host"); the actual culprit turned out to be the
  router. OrbStack's VM forwards pod DNS through `0.250.250.200` → the host
  resolver, so it inherits any host flakiness. Worse in the ~15 min after any
  OrbStack restart. The `fetch` task is byte-identical to when Slice 4's e2e
  passed 21/21.
- **Check:** from a pod, `dig +short A github.com @0.250.250.200` in a loop —
  if it drops >10% it is this. From the Mac, `curl -4 -m5 https://github.com`
  a few times.
- **Fix (host / network, the real one):** the router; failing that, disconnect
  the flaky VPN, set an explicit IPv4 resolver (`1.1.1.1` / `9.9.9.9`) in macOS
  Network settings, or `sudo dscacheutil -flushcache && sudo killall -HUP
  mDNSResponder`.
- **Mitigation (in-repo):** the `fetch` step retries `git fetch` up to 5× with
  backoff on transient network errors only (a bad ref still fails fast).
  Absorbs a single blip; a sustained outage still fails.
- **Do NOT** `bufsize 512` on CoreDNS — tried, does not help (the proxy drops
  queries regardless of EDNS once degraded).

### A pipeline acceptance test fails at the first TaskRun with `serviceaccount ... not found`

- **Likely cause:** the Chainsaw `apply` of `tests/_resources/pipeline-rbac.yaml`
  did not run, or the shared ClusterRoles (`cv-smoke-role` / `cv-deploy-role`)
  are not on the cluster (they come from `manifests/rbac.yaml` via
  `bootstrap.sh` phase 3, not from the test).
- **Check:** `kubectl get clusterrole cv-smoke-role cv-deploy-role`;
  `kubectl -n <test-ns> get sa,rolebinding`.
- **Fix:** re-run `bootstrap.sh` phase 3, or `kubectl apply -f manifests/rbac.yaml`.

## Slice 5b

### build the render image (`zot/timoni`)

Timoni ships no container image. `deploy` / `smoke` run `timoni build` from a
vendored scratch image. Rebuild + re-push + bump `digests.cue` `timoniImage`
on a Timoni version bump — the full `crane` sequence and the pinned inputs are
in `vendor/render/README.md`. Needs `crane` + reachable zot
(`kubectl -n cv-pipeline port-forward svc/zot 5000:5000` or the OrbStack route).
`tofu/` (Slice 5c) automates this.

### `deploy` / `smoke` render step fails: `modules/web-app/ missing from config-ref`

- **Cause:** the `fetch-config` step checked out `cv_oci@<pipeline-ref>` and
  `modules/web-app/` was not there. `pipeline-ref` defaults to `main`; the
  acceptance suites pass `$(git rev-parse HEAD)`, which **must be pushed** —
  `git fetch origin <sha>` only works for a commit reachable from a remote ref.
- **Fix:** push the branch (or pass a `pipeline-ref` that has `modules/`).

### render step fails: `stat /tmp: no such file` or a cache-dir error

- **Cause:** the render image is scratch — no `/tmp`, no writable `$HOME`.
- **Fix:** the render step sets `TMPDIR=$WS/render/tmp` (write-values `mkdir`s
  it) and `TIMONI_CACHING=false`. If you see this, one of those was dropped.

### render step: `translating TaskSpec to Pod: ... x509: certificate signed by unknown authority`

- **Cause:** with no explicit `command:`, the Tekton controller does a registry
  lookup to resolve the render image's ENTRYPOINT and cannot verify zot's
  self-signed cert (Slice 4 T3 — CA not distributed to the Pipelines controller).
- **Fix:** the render step is a `script:` step (explicit `#!/bin/sh` — the image
  has a static busybox), so Tekton needs no entrypoint lookup. Do not switch it
  to `command:`/`args:` without giving the controller the zot CA.

## Slice 5c-A

### `tofu apply` — first run

Prereqs: `bootstrap.sh` has run (zot + Chains + `signing-secrets` +
`zot-tls`). Then:

```sh
cd tofu
tofu init      # downloads alekc/kubectl + hashicorp/kubernetes
tofu apply
```

`tofu apply` is idempotent — re-running on a provisioned cluster is a no-op.
`tofu destroy` removes Flux + the CRs and leaves `bootstrap.sh`'s layer intact.

### `deploy` step fails: `flux push artifact ... x509: certificate signed by unknown authority`

- **Cause:** the `publish-artifact` step reaches zot over HTTPS with a
  cert-manager self-signed CA. `flux push artifact` (v2.9.4) has no `--ca-file`
  flag — it reads the CA from `SSL_CERT_FILE`.
- **Fix:** the step mounts `zot-tls` `ca.crt` at `/tls/ca.crt` and sets
  `SSL_CERT_FILE=/tls/ca.crt`. In an ephemeral test namespace `zot-tls` must be
  copied in first (the Chainsaw `pipeline-acceptance` setup does this). Do NOT
  use `--insecure-registry` — that is plain HTTP, zot is HTTPS.

### `deploy` fails: `deploy needs a 40-hex cv_frontend sha`

- **Cause:** `flux push artifact --revision` needs `cv-frontend@sha1:<40-hex>`.
  The deploy step asserts `app-sha` is a full commit SHA. A branch name or short
  SHA fails here.
- **Fix:** pass `frontend-ref` as a full 40-char SHA (reconstruction pins it
  anyway). The negative suites use branch names but never reach `deploy`.

### OCIRepository stuck `Ready=False [VerificationError] no matching signatures`

- **Expected transient** right after a deploy: Chains signs the artifact async
  (~15s, minutes under load). The `OCIRepository` (`interval: 1m`) self-heals
  once the `sigstore-bundle` referrer lands (P12).
- **If it never clears:** check `kubectl -n tekton-chains logs deploy/tekton-chains-controller`
  for the `deploy` TaskRun — Chains only signs when the TaskRun emitted
  `manifests_IMAGE_URL` (bare repo, no `@`) + `manifests_IMAGE_DIGEST`
  (`sha256:…`). An `_ARTIFACT_OUTPUTS` object is silently ignored ("No image
  subject to attest").
- **Wrong key:** `cosign-public-key` in `flux-system` must be the current
  `tekton-chains/signing-secrets` `cosign.pub`. `tofu apply` re-copies it.

### `tests/deploy-via-flux` — the reconcile suite

Runs a real `cv-build` PipelineRun into `cv-pipeline` and drives the Flux
reconcile (verify, apply, drift-revert, tamper-reject). Needs `tofu apply`
first — its preflight step fails clean otherwise. Heavier than the other
suites (~12min pipeline + Flux latency) and it mutates prod `cv-pipeline`
state (leaves `cv` deployed). It also pushes an accumulating CalVer tag to
`zot/cv-frontend` each run — folded into the existing zot-retention TODO.

If it leaves the `OCIRepository` stuck at `VerificationError` after the
tamper step (bad tag not cleaned):
`crane delete --insecure zot.cv-pipeline.svc.cluster.local:5000/cv-frontend:0.99999999.0`
then `kubectl -n flux-system annotate --overwrite ocirepository/cv-frontend
reconcile.fluxcd.io/requestedAt="$(date +%s)"`.

### Re-vendoring `tofu/flux/components.yaml` on a Flux bump

`flux install --export --components=source-controller,kustomize-controller
--namespace=flux-system --network-policy=true > tofu/flux/components.yaml`, then
re-apply the three local edits documented in the file header (2 image pins from
`digests.cue` + the `flux-system` Namespace `enforce=restricted` labels). Bump
`digests.cue` `fluxSourceController` / `fluxKustomizeController` /
`fluxCli` with `crane digest --platform linux/arm64` and regen.
