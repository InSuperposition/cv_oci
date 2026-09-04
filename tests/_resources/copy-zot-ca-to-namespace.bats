#!/usr/bin/env bats
# Tests for tests/_resources/copy-zot-ca-to-namespace.sh — a thin `kubectl`
# wrapper (get the CA from cv-pipeline, recreate it in $NS). PATH-stubbed.

load ../_resources/stub-helpers

setup() {
	ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	cd "$ROOT"
	SCRIPT=tests/_resources/copy-zot-ca-to-namespace.sh
	stub_init
	# base64 of "fake-ca-bytes", the get-secret stub prints it back.
	stub kubectl "$(cat <<'STUB'
case "$1" in
  get) printf 'ZmFrZS1jYS1ieXRlcw==' ;;
  create) cat <<YAML
apiVersion: v1
kind: Secret
metadata: {name: zot-tls, namespace: chainsaw-abc}
YAML
    ;;
  apply) cat >/dev/null ;;
esac
STUB
)"
}

teardown() { rm -rf "$STUB_BIN"; }

@test "requires NS" {
	run env -u NS bash "$SCRIPT"
	[ "$status" -ne 0 ]
}

@test "reads the CA from cv-pipeline's zot-tls secret" {
	NS=chainsaw-abc run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	get_args=$(stub_calls kubectl | jq -sc '[.[] | select(.args[0]=="get")][0].args')
	[ "$get_args" = '["get","secret","zot-tls","-n","cv-pipeline","-o","jsonpath={.data.ca\\.crt}"]' ]
}

@test "recreates zot-tls in NS via dry-run|apply, not a direct create" {
	# create | apply is a shell pipeline — both stubs run concurrently, so
	# match by verb (args[0]), never by call-index — the log order between
	# two processes racing on the same fd is not guaranteed.
	NS=chainsaw-abc run bash "$SCRIPT"
	create_args=$(stub_calls kubectl | jq -sc '[.[] | select(.args[0]=="create")][0].args')
	echo "$create_args" | jq -e 'contains(["-n","chainsaw-abc"]) and contains(["--dry-run=client"])' >/dev/null
	apply_args=$(stub_calls kubectl | jq -sc '[.[] | select(.args[0]=="apply")][0].args')
	[ "$apply_args" = '["apply","-n","chainsaw-abc","-f","-"]' ]
}

@test "prints {namespace,secret}" {
	NS=chainsaw-abc run bash "$SCRIPT"
	[ "$output" = '{"namespace":"chainsaw-abc","secret":"zot-tls"}' ]
}
