# render image — `zot/timoni`

A **scratch** image containing only the pinned Timoni CLI. The `deploy` and
`smoke` pipeline tasks run `timoni build ./modules/web-app` in a step that uses
it (Slice 5b). Timoni publishes no container image of its own (v0.33.0 ships
binary tarballs only), so cv_oci vendors one.

No shell, no base OS — `timoni` is a static Go binary and the render step
invokes it via `command:` / `args:`, never `script:`. The step's stdout is
captured to the workspace by Tekton `stdoutConfig`.

## Pinned inputs

| | Value |
|---|---|
| Timoni version | `0.33.0` (`docs/bootstrap-toolchain.md`) |
| `timoni_0.33.0_linux_arm64.tar.gz` sha256 | `79fe26b750084f069540941990eb2eae7eb20ec5640ed92b2029002fda41be24` (from the release `checksums.txt`) |
| image digest | `digests.cue` `images.timoniImage` |

## Rebuild (on a Timoni version bump)

`docker build` is not used — OrbStack's daemon emits Docker-media-type
manifests that zot 2.1.5 rejects, and buildah/podman are not set up. The image
is assembled with `crane` from the checksum-verified binary:

```sh
ver=0.33.0
sha=79fe26b750084f069540941990eb2eae7eb20ec5640ed92b2029002fda41be24
zot=zot.cv-pipeline.svc.cluster.local:5000            # via kubectl port-forward or the OrbStack service route

curl -sL -o /tmp/t.tgz "https://github.com/stefanprodan/timoni/releases/download/v${ver}/timoni_${ver}_linux_arm64.tar.gz"
printf '%s  /tmp/t.tgz\n' "$sha" | shasum -a 256 -c -
mkdir -p /tmp/rb/usr/local/bin
tar -xzf /tmp/t.tgz -C /tmp/rb/usr/local/bin timoni
( cd /tmp/rb && tar --format=ustar -cf /tmp/layer.tar usr )

crane append --oci-empty-base --insecure -f /tmp/layer.tar -t "$zot/timoni:build-stage"
crane mutate --insecure "$zot/timoni:build-stage" \
  --set-platform linux/arm64 --entrypoint /usr/local/bin/timoni -u 1000 \
  -t "$zot/timoni:${ver}"
crane delete --insecure "$zot/timoni:build-stage"
crane digest --insecure "$zot/timoni:${ver}"          # -> bump digests.cue images.timoniImage
```

`tofu/` (Slice 5c) automates this rebuild+push; until then it is a manual step
recorded here and in `docs/runbook.md`.
