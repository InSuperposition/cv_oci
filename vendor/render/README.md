# render image — `zot/timoni`

A near-scratch image: the pinned static Timoni CLI + a static busybox for
`/bin/sh`, nothing else. The `deploy` and `smoke` pipeline tasks run
`timoni build ./modules/web-app` in a `script:` step that uses it (Slice 5b).
Timoni publishes no container image of its own (v0.33.0 ships binary tarballs
only), so cv_oci vendors one.

`/bin/sh` (busybox, static-pie) is there only so the render step can be a
`script:` step — `timoni build` writes to a workspace file and Tekton's
`stdoutConfig` (the shell-free alternative) needs `enable-api-fields: alpha`,
which would mean a cluster-config step outside the frozen `bootstrap.sh`.

## Pinned inputs

| | Value |
|---|---|
| Timoni version | `0.33.0` (`docs/bootstrap-toolchain.md`) |
| `timoni_0.33.0_linux_arm64.tar.gz` sha256 | `79fe26b750084f069540941990eb2eae7eb20ec5640ed92b2029002fda41be24` (from the release `checksums.txt`) |
| busybox | `docker.io/library/busybox:musl` (arm64, static-pie), `/bin/busybox` + a `bin/sh` symlink |
| image digest | `digests.cue` `images.timoniImage` |

## Rebuild (on a Timoni version bump)

`docker build` is not used — OrbStack's daemon emits Docker-media-type
manifests that zot 2.1.5 rejects, and buildah/podman are not set up. The image
is assembled with `crane` from the checksum-verified binary:

```sh
ver=0.33.0
sha=79fe26b750084f069540941990eb2eae7eb20ec5640ed92b2029002fda41be24
zot=zot.cv-pipeline.svc.cluster.local:5000            # via kubectl port-forward or the OrbStack service route
rb=$(mktemp -d)

curl -sL -o "$rb/t.tgz" "https://github.com/stefanprodan/timoni/releases/download/v${ver}/timoni_${ver}_linux_arm64.tar.gz"
printf '%s  %s/t.tgz\n' "$sha" "$rb" | shasum -a 256 -c -
mkdir -p "$rb/root/usr/local/bin" "$rb/root/bin"
tar -xzf "$rb/t.tgz" -C "$rb/root/usr/local/bin" timoni
crane export docker.io/library/busybox:musl --platform linux/arm64 - | tar -xf - -C "$rb" bin/busybox
cp "$rb/bin/busybox" "$rb/root/bin/busybox"
ln -s busybox "$rb/root/bin/sh"
( cd "$rb/root" && tar --format=ustar -cf "$rb/layer.tar" usr bin )

crane append --oci-empty-base --insecure -f "$rb/layer.tar" -t "$zot/timoni:build-stage"
crane mutate --insecure "$zot/timoni:build-stage" \
  --set-platform linux/arm64 --entrypoint /usr/local/bin/timoni -u 1000 \
  -t "$zot/timoni:${ver}"
crane delete --insecure "$zot/timoni:build-stage"
crane digest --insecure "$zot/timoni:${ver}"          # -> bump digests.cue images.timoniImage
```

`tofu/` (Slice 5c) automates this rebuild+push; until then it is a manual step
recorded here and in `docs/runbook.md`.
