// digests.cue — single source of truth for every pinned image digest.
//
// Never edit digests.env or params.yaml by hand. Edit here, then run
// `scripts/gen-digests.sh` and commit all three.
//
// A value of "" means "not yet pinned". gen-digests.sh skips empty entries;
// any script or Task that needs an unpinned digest must fail loudly (Rule 13).
// Digests are filled in as each slice lands its component.
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
frontend: fixtureSha: "cb333ee18646e1d97eab592547fe09cbef83727b"

images: [string]: #Pin

images: {
	// --- the CNB pipeline (docs/designs/buildpacks-pivot.md) ---

	// docker.io/heroku/builder:24 — the CNB builder. arm64 CHILD digest (native
	// build on the arm64 node). Every paketobuildpacks builder is amd64-only
	// (probed 2026-09-01); Heroku's is genuinely multi-arch. See docs/gate-zero.md.
	cnbBuilder: "sha256:e74d36e0e70f9b588f62483bef73a51809c1f51f04103dbb323293261bfc43aa"
	// docker.io/heroku/heroku:24 — the CNB run image. arm64 child digest.
	cnbRunImage: "sha256:d7a262713dc2686f231416b3a2b82796d42eeca31bc2f0b9b8eac747b456f7a9"
	// docker.io/library/bash:5.1.4 — the vendored buildpacks task's prepare/results
	// step image (multi-arch; upstream tektoncd/catalog pins this tag).
	cnbUtilityImage: "sha256:b208215a4655538be652b2769d82e576bc4d0a2bb132144c060efc5be8c3f5d6"
	// docker.io/alpine/k8s:1.31.1 — the smoke/deploy step runner (kubectl + curl
	// + bash). arm64 child digest.
	cnbKubectlImage: "sha256:4a54840ba92ee07478bfdb5daf09d1e8ef16657dda92cfe8677c6baf557a7ea0"
	// docker.io/alpine/git:latest — the fetch step. arm64 child digest.
	cnbGitImage: "sha256:922e413cfcd642ee87eda2da02462d86544ce3d2d0a0e43da1f3b83aabcb5730"
	// ghcr.io/project-zot/zot-minimal-linux-arm64:v2.1.5 — the in-cluster
	// registry seed. arm64-native image.
	zot: "sha256:55eafc5a16b0efb965786ccf75cd5fb7f76e3832a8bcd7f0da3983e689039a69"

	// Slice 3 — Trivy CVE gate.
	// trivyCli: ghcr.io/aquasecurity/trivy:0.74.0, arm64 child (the scan step
	// runs on the arm64 node). trivyDb: ghcr.io/aquasecurity/trivy-db:2,
	// pinned by digest so the CVE verdict is reproducible — (app digest, DB
	// digest) determines the verdict. The scan step passes
	// `--db-repository ghcr.io/aquasecurity/trivy-db@<trivyDb>` and the tests
	// pin the same DB, so a frozen fixture SBOM always yields the same answer.
	trivyCli: "sha256:55ad20f8a239a3e95427e60b8aaea38788550c18a3f1772976bebf732e6ae166"
	trivyDb:  "sha256:35f26e97af328ec930bf41d86c6a34ca68c11d32ccd10d3de2b7ad856ed6e084"

	// ghcr.io/oras-project/oras:v1.2.3 — arm64 child. The `scan` task's
	// `referrers` step `oras attach`es the CycloneDX SBOM + the CVE-verdict
	// record to the app digest (Slice 4 T5). Tekton Chains attaches the SLSA
	// provenance the same way (OCI 1.1 Referrers API).
	orasCli: "sha256:c4d59cab4aa6d6cfb8e3c31b571f5af5086004f3fe28700b844a14660bf0c9c4"

	// Slice 4
	cosignCli: ""
	chains:    "" // ghcr.io/tektoncd/chains

	// Slice 5b — the render image: a scratch image holding only the pinned
	// Timoni CLI, used by the `deploy` / `smoke` render steps to
	// `timoni build ./modules/web-app`. Timoni ships no image of its own;
	// cv_oci builds one from the checksum-verified binary — see
	// `vendor/render/README.md`. Lives in the in-cluster registry only
	// (`zot/timoni`), so this is a bare digest, not a repo@digest ref.
	timoniImage: "sha256:1d8af7e07438b9a13e8e566ba5b1829f7127832096f0c86252f600d5eb2eb873"
}
