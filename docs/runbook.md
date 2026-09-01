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

### OrbStack image-pull facts (why Slice 1 has no registry)

Verified 2026-08-30 on OrbStack k8s `v1.35.6+orb1` (runtime `docker://29.4.0`):

- Image pulls go through the **OrbStack Docker daemon** (cri-dockerd).
- That daemon **cannot resolve `*.svc.cluster.local`** — it uses OrbStack DNS
  (`0.250.250.200`) and times out. A ClusterIP `.svc` registry name is unusable
  for kubelet pulls.
- It requires **HTTPS** unless the registry is in `insecure-registries`
  (`~/.orbstack/config/docker.json`, edited via `orb config docker` — restarts
  the docker engine, not the whole VM).
- **NodePort is not routed to the host** (`k8s.expose_services: false`);
  enabling it needs a full `orb stop` / restart.
- **OrbStack k8s reads the host Docker image store** — an image `docker load`ed
  locally runs with `imagePullPolicy: Never`, no registry.
- In-cluster pods reach ClusterIPs and `.svc` names fine.

Slice 1 therefore uses `crane` → tarball → `docker load` → run by digest. zot and
a real pull-trust path arrive at Slice 3.

### CNB pivot — the zot pull path (supersedes some of the above)

Verified 2026-09-01 while wiring `pipeline/pipeline-cnb.yaml`. The 2026-08-30
"daemon cannot resolve `*.svc`" finding was taken with `k8s.expose_services:
false`. Turning it on changes the picture:

```
orb config set k8s.expose_services true      # then: orb stop / restart
# ~/.orbstack/config/docker.json:
{"insecure-registries":["zot.cv-pipeline.svc.cluster.local:5000"]}
orb restart docker                            # ~30s, restarts the k8s cluster
```

With those two settings the OrbStack Docker daemon (the kubelet's puller) DOES
resolve and pull plain-HTTP from `zot.cv-pipeline.svc.cluster.local:5000`.
Because OrbStack routes that name to both the in-cluster network and the Mac
daemon, **one address serves push and pull** — no two-address split, no
hostPort. (hostPort on `127.0.0.1` does not work on OrbStack anyway: the VM
loopback is forwarded to the Mac loopback, and `:5000` there is macOS AirPlay
Receiver — `Server: AirTunes`.)

`k8s.expose_services` + the `insecure-registries` entry are the documented
per-platform node steps. A portable cluster substitutes its own registry
ingress + trust config.

## Slice 1

### `scripts/test/e2e.sh` or `negative.sh` fails

- **Check:** `e2e.sh --keep` leaves the `cv-e2e-<uid>` namespace + the run
  evidence in `scripts/test/_artifacts/<ns>/` (pipelinerun.yaml, taskruns.yaml,
  events.txt, pipeline.log, pods.txt, deployed.yaml). Read `pipeline.log` first.
- **Common causes:** cluster DNS blip in a Task pod (`resolve` retries the
  clone 3x — if it still fails, `kubectl -n kube-system rollout restart deploy
  coredns`); the `cv/pipeline-utils:slice1-arm64` image is stale
  (`bootstrap/build-pipeline-utils.sh` to rebuild + `--check` for the digest);
  Service-endpoint lag (smoke retries `/healthz` 10x — a persistent failure
  means the image genuinely doesn't serve).
- **Cleanup after `--keep`:** `kubectl delete ns cv-e2e-<uid>`;
  `docker rmi cv:git-<sha>`; `rm -rf scripts/test/_artifacts`.

### A PipelineRun is stuck / a stale `cv` Deployment is running

- **Rollback:** `kubectl -n cv-pipeline rollout undo deploy/cv`, or
  `kubectl -n cv-pipeline set image deploy/cv app=$(kubectl -n cv-pipeline get
  cm cv-deploy-state -o jsonpath='{.data.previous}')`. Find the last-good tag in
  the `cv-deploy-state` ConfigMap or `kubectl rollout history deploy/cv`.

### `cue vet digests.cue` fails with a constraint error

- **Likely cause:** a digest value is not `sha256:` + 64 hex chars (a tag slipped
  in, or a truncated digest).
- **Check:** the error names the field.
- **Fix:** put the full `sha256:...` digest in. Get it with
  `crane digest <ref>` (Slice 1+) or from the source registry's UI.
