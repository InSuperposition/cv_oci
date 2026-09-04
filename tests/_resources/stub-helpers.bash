#!/usr/bin/env bash
# stub-helpers.bash — bats test helper for PATH-stubbing external tools
# (kubectl/oras/cosign/crane/...) so a tests/_resources/ wrapper script's
# command construction can be asserted without a cluster or a registry.
#
# `load ../_resources/stub-helpers` from a *.bats file (bats resolves `load`
# relative to $BATS_TEST_DIRNAME), then in setup(): stub_init; PATH stays
# stubbed only for that test's subshells.
#
#   stub_init                       — fresh scratch bin dir, prepend to PATH
#   stub <tool> [<script-body>]     — write an executable $STUB_BIN/<tool>.
#                                     Every call is recorded as one JSON line
#                                     ({"tool":..,"args":[..]}) BEFORE
#                                     <script-body> runs, so the recording
#                                     survives even if the body exits non-zero.
#                                     <script-body> is a shell snippet with
#                                     "$@" in scope; omit it for a silent,
#                                     exit-0 stub.
#   stub_calls <tool>                — one JSON line per call to <tool>, in
#                                     invocation order (jq -c, newline-joined).
#   stub_call_args <tool> <n>        — the .args array of the nth (0-based)
#                                     call to <tool>, jq -c.
set -u

stub_init() {
	STUB_BIN=$(mktemp -d)
	STUB_CALLS="$STUB_BIN/.calls.jsonl"
	: >"$STUB_CALLS"
	PATH="$STUB_BIN:$PATH"
}

stub() {
	local tool=$1 body=${2:-}
	cat >"$STUB_BIN/$tool" <<STUB_EOF
#!/usr/bin/env bash
jq -nc --arg tool "$tool" --args '{tool: \$tool, args: \$ARGS.positional}' -- "\$@" >> "$STUB_CALLS"
$body
STUB_EOF
	chmod +x "$STUB_BIN/$tool"
}

stub_calls() {
	jq -c --arg t "$1" 'select(.tool == $t)' "$STUB_CALLS"
}

stub_call_args() {
	jq -sc --arg t "$1" --argjson n "$2" \
		'[.[] | select(.tool == $t)] | .[$n].args' "$STUB_CALLS"
}
