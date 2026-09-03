// Sample values so `timoni mod vet` and CI can validate the module offline.
// Not used by any real instance — every deploy supplies its own image.
values: {
	image:      "example.test/web-app@sha256:0000000000000000000000000000000000000000000000000000000000000000"
	appVersion: "0.0.0-sample"
}
