#!/usr/bin/env bats
# Tests for scripts/validate.sh.

setup() {
	ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	cd "$ROOT"
}

@test "valid fixture passes validate.sh" {
	run scripts/validate.sh scripts/test/fixtures/valid-configmap.yaml
	[ "$status" -eq 0 ]
}

@test "broken fixture fails validate.sh" {
	run scripts/validate.sh scripts/test/fixtures/broken-configmap.yaml
	[ "$status" -ne 0 ]
}

@test "validate.sh exits 0 when there are no manifests to check" {
	# Slice 0 state: no tracked *.yaml outside schemas/ and fixtures.
	run scripts/validate.sh
	[ "$status" -eq 0 ]
}

@test "validate.sh flags a hard-coded image reference" {
	tmp="$(mktemp -d)"
	cat > "$tmp/deploy.yaml" <<-'EOF'
		apiVersion: apps/v1
		kind: Deployment
		metadata:
		  name: x
		spec:
		  selector: { matchLabels: { app: x } }
		  template:
		    metadata: { labels: { app: x } }
		    spec:
		      containers:
		        - name: c
		          image: nginx:1.25
	EOF
	run scripts/validate.sh "$tmp/deploy.yaml"
	rm -rf "$tmp"
	[ "$status" -ne 0 ]
}

@test "validate.sh accepts a param-fed image reference" {
	tmp="$(mktemp -d)"
	cat > "$tmp/deploy.yaml" <<-'EOF'
		apiVersion: apps/v1
		kind: Deployment
		metadata:
		  name: x
		spec:
		  selector: { matchLabels: { app: x } }
		  template:
		    metadata: { labels: { app: x } }
		    spec:
		      containers:
		        - name: c
		          image: $(params.craneCli-digest)
	EOF
	run scripts/validate.sh "$tmp/deploy.yaml"
	rm -rf "$tmp"
	[ "$status" -eq 0 ]
}
