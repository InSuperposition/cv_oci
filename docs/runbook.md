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

### `scripts/test/e2e.sh` or `negative.sh` fails

- **Check:** `e2e.sh --keep` leaves the `cv-cnb-e2e-<uid>` namespace, the
  run-scoped zot repo, and the evidence in `scripts/test/_artifacts/<ns>/`
  (pipelinerun.yaml, taskruns.yaml, events.txt, pipeline.log, deployed.yaml).
  Read `pipeline.log` first.
- **Common causes:** the OrbStack node-trust steps above are not done (the `cv`
  pod `ErrImagePull`s or gets `http: server gave HTTP response to HTTPS
  client`); cluster DNS blip in a Task pod (`fetch` clones shallow — retry the
  run); Service-endpoint lag (smoke/deploy retry `/healthz` 10x — a persistent
  failure means the image genuinely doesn't serve); zot PVC full.
- **Cleanup after `--keep`:** `kubectl delete ns cv-cnb-e2e-<uid>`;
  `kubectl -n cv-pipeline exec deploy/zot -- rm -rf /var/lib/registry/cv-e2e-<uid>`;
  `rm -rf scripts/test/_artifacts`.

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

- **Not a bug** — the lifecycle is not byte-reproducible without
  `SOURCE_DATE_EPOCH` + layer normalisation (Slice 2, `docs/debt.md`). Assert
  equal SBOM package set + app-layer content hash, never raw digest.
