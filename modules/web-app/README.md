# web-app

A [Timoni](https://timoni.sh) module that renders **one Deployment + one
ClusterIP Service** for a stateless HTTP web app, with the PodSecurity
`restricted` container context the cv_oci pipeline enforces.

The name is deliberately consumer-agnostic. `cv-frontend` is the first
instance; the `deploy` and `smoke` pipeline tasks both render from this module
(Slice 5b, `docs/designs/buildpacks-pivot.md`).

## Build

```shell
timoni build cv-frontend ./modules/web-app -n cv-pipeline -f values.cue
```

`timoni build` is byte-deterministic given `(module, values)` — verified across
repeated runs, cache on/off/cleared, and with no cluster reachable (P13). The
CUE language pin lives in `cue.mod/module.cue` (`language.version`); `timoni`
and `cue` versions are pinned in `docs/bootstrap-toolchain.md` and are the only
reproduction inputs beyond the module source and values.

`timoni build -v <version>` is **ignored for a local-path module** — pass
`appVersion` in the values instead (see below).

## Values

| Field | Type | Default | Notes |
|---|---|---|---|
| `image` | string (`repo@sha256:…`) | **required** | Full digest-pinned ref. Never pinned in the module — every instance supplies it (for `cv-frontend`, the `build` task result). |
| `appVersion` | string | `moduleVersion` | Stamped as `app.kubernetes.io/version`. For `cv-frontend` = the checked-out cv_frontend commit SHA. |
| `port` | int | `44100` | `PORT` env + `containerPort`; the Service exposes it on `:80`. |
| `readinessPath` | string | `/healthz` | Readiness probe HTTP path. |
| `replicas` | int | `1` | |
| `selectorLabels` | map | `{app: <name>}` | Deployment + Service selector. Stable per instance. |
| `extraLabels` | map | — | Merged onto every object's `metadata.labels` and the pod template (not the selector). Used by `smoke` for its run-id teardown label. |
| `extraEnv` | `[]EnvVar` | — | Extra container env. |
| `securityContext` | `SecurityContext` | restricted | `runAsNonRoot`, uid/gid 1000, no privilege escalation, drop ALL caps, `RuntimeDefault` seccomp. Overridable but defaults match the inline pipeline steps. |

## Validate

```shell
timoni mod vet ./modules/web-app -f ./modules/web-app/test/values.cue
```

## Vendored schema

`cue.mod/gen/` (k8s API) and `cue.mod/pkg/timoni.sh/` (Timoni schema) are
vendored by `timoni mod init` / `timoni mod vendor` and committed as generated.
