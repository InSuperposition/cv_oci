// digests.cue — single source of truth for every pinned image digest.
//
// Never edit digests.env or params.yaml by hand. Edit here, then run
// `scripts/gen-digests.sh` and commit all three.
//
// A value of "" means "not yet pinned". gen-digests.sh skips empty entries;
// any script or Task that needs an unpinned digest must fail loudly (Rule 13).
// Digests are filled in as each slice lands its component — see
// docs/bootstrap-toolchain.md for the two-phase pipelineUtils flow.
package digests

#Digest:  =~"^sha256:[0-9a-f]{64}$"
#Pin:     #Digest | ""
#GitSha:  =~"^[0-9a-f]{40}$"

// cv_frontend pin. Each cv_oci commit pins a known-good cv_frontend commit so
// acceptance (`npm test`, the e2e) is meaningful at any checkout (codex #13).
frontend: {
	repo:       "https://github.com/InSuperposition/cv_frontend"
	fixtureSha: #GitSha | ""
}
frontend: fixtureSha: "d7f14b797ac83dd618040e65c4a65196eba37b9a"

images: [string]: #Pin

images: {
	// Slice 1
	// gcr.io/distroless/nodejs24-debian12:nonroot — the runtime base.
	// This is the linux/arm64 CHILD digest (not the multi-arch index); Slice 1
	// is arm64-only. Slice 5 makes the base arch-aware.
	distrolessNode: "sha256:0d757b971ffc552eeb69e4f13b9223b36d79fb28ccb5425f33bf044dd7760b25"
	// built out-of-cluster by bootstrap/build-pipeline-utils.sh (two-phase, see
	// docs/bootstrap-toolchain.md). Rebuild + repin when apko.yaml or scripts/ change.
	pipelineUtils: "sha256:2868a1ddbd8efe39c1fb58f9b2fb022cc09c0187c11fef2cca0481538a03cc09"

	// docker.io/library/node:24-bookworm-slim — the build Task image. MUST be
	// debian/glibc + arm64 to match the distroless runtime base: the app's
	// native deps (oxc-transform, esbuild, lightningcss) ship per-libc bindings
	// (linux-arm64-gnu), so `npm ci` runs here, not in the musl pipeline-utils.
	nodeBuild: "sha256:e9b5516b06baeaea9a8e65a7aec6a85fbb960a30b52b66968f2c8092b3e2a3eb"

	// Slice 3
	trivyCli: ""

	// Slice 4
	cosignCli: ""
	chains:    "" // ghcr.io/tektoncd/chains
}
