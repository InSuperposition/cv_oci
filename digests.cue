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
	// gcr.io/distroless/nodejs24-debian12:nonroot — the runtime base
	distrolessNode: "sha256:14d42e2511532589a7c7e01a753667a74fcc96266e137e8125006b87b0c32d0a"
	// built out-of-cluster by bootstrap/build-pipeline-utils.sh (two-phase, see
	// docs/bootstrap-toolchain.md). Rebuild + repin when apko.yaml or scripts/ change.
	pipelineUtils: "sha256:0e4012c8891c7b731dbb1be1f8a92e6269f0a6b08a280712a7f99e3e99c3f8c1"

	// Slice 3
	trivyCli: ""

	// Slice 4
	cosignCli: ""
	chains:    "" // ghcr.io/tektoncd/chains
}
