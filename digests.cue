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
	distrolessNode: "" // gcr.io/distroless/nodejs24-debian12:nonroot
	craneCli:       "" // gcr.io/go-containerregistry/crane
	pipelineUtils:  "" // built out-of-cluster by bootstrap.sh, two-phase

	// Slice 3
	trivyCli: ""

	// Slice 4
	cosignCli: ""
	chains:    "" // ghcr.io/tektoncd/chains
}
