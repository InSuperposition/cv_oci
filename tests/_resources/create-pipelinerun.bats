#!/usr/bin/env bats
# Tests for tests/_resources/create-pipelinerun.sh — the shared PipelineRun
# renderer. DRY_RUN mode makes it a pure function of its env + digests.env, so
# it is unit-testable without a cluster.

setup() {
	ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	cd "$ROOT"
	SCRIPT=tests/_resources/create-pipelinerun.sh
	export DRY_RUN=1
}

render() { # render NS LABEL [extra env already exported]
	NS="$1" ACCEPTANCE_LABEL="$2" bash "$SCRIPT"
}

@test "requires NS" {
	run env -u NS ACCEPTANCE_LABEL=x bash "$SCRIPT"
	[ "$status" -ne 0 ]
}

@test "requires ACCEPTANCE_LABEL" {
	run env -u ACCEPTANCE_LABEL NS=x bash "$SCRIPT"
	[ "$status" -ne 0 ]
}

@test "DRY_RUN renders a PipelineRun and does not touch the cluster" {
	run render chainsaw-xyz pipeline-acceptance
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '^kind: PipelineRun$'
	echo "$output" | grep -q 'name: cv-build'
}

@test "metadata.name is deterministic (default: run)" {
	run render chainsaw-xyz pipeline-acceptance
	echo "$output" | grep -q '^  name: run$'
	run env RUN_NAME=deploy-via-flux-run NS=cv-pipeline ACCEPTANCE_LABEL=deploy-via-flux bash "$SCRIPT"
	echo "$output" | grep -q '^  name: deploy-via-flux-run$'
}

@test "always emits all three taskRunSpecs" {
	run render chainsaw-xyz pipeline-acceptance
	echo "$output" | grep -q 'pipelineTaskName: smoke$'
	echo "$output" | grep -q 'pipelineTaskName: smoke-teardown'
	echo "$output" | grep -q 'pipelineTaskName: deploy'
}

@test "image params are digest-pinned from digests.env" {
	# shellcheck source=/dev/null
	. ./digests.env
	run render chainsaw-xyz pipeline-acceptance
	echo "$output" | grep -q "docker.io/heroku/builder:24@${CNBBUILDER}"
	echo "$output" | grep -q "ghcr.io/fluxcd/flux-cli@${FLUXCLI}"
	# no bare tags on the CNB images
	! echo "$output" | grep -E 'heroku/builder:24"$'
}

@test "per-suite variance: NS, FRONTEND_REF, APP_REPO" {
	run env NS=chainsaw-abc ACCEPTANCE_LABEL=pipeline-rejects-bad-ref \
		FRONTEND_REF=no-such-branch APP_REPO=zot.example:5000/chainsaw-abc \
		bash "$SCRIPT"
	echo "$output" | grep -q 'namespace: chainsaw-abc'
	echo "$output" | grep -q 'value: "no-such-branch"'
	echo "$output" | grep -q 'value: "zot.example:5000/chainsaw-abc"'
	# deploy-artifact-repo defaults to <APP_REPO>-frontend
	echo "$output" | grep -q 'value: "zot.example:5000/chainsaw-abc-frontend"'
}

@test "rendered manifest passes kubeconform" {
	run render chainsaw-xyz pipeline-acceptance
	[ "$status" -eq 0 ]
	tmp="$BATS_TEST_TMPDIR/pr.yaml"
	printf '%s\n' "$output" > "$tmp"
	run kubeconform -strict \
		-schema-location 'schemas/{{ .Group }}/{{ .ResourceKind }}_{{ .ResourceAPIVersion }}.json' \
		-schema-location 'https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/v1.31.0-standalone-strict/{{ .ResourceKind }}{{ .KindSuffix }}.json' \
		"$tmp"
	[ "$status" -eq 0 ]
}
