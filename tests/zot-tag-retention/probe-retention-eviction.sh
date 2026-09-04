#!/usr/bin/env bash
# probe-retention-eviction.sh — prove pushedWithin actually evicts aged tags,
# keeps in-window tags, and spares a repo matching no policy — against a
# throwaway zot container with a 5s window so the test does not wait 168h.
#
# Irreducible: this spins up a real zot (same pinned image as the live
# registry), pushes three tiny tags, waits one GC pass, and inspects what
# survived. No Kubernetes involved.
#
#   {"aged":[...],"fresh":[...],"unmatched":[...],"delete_logged":bool}
#
# A chainsaw assert: tree checks: aged is empty, fresh contains "v1", unmatched
# contains "v1", and a retention "delete" decision was logged for evict-aged.
set -euo pipefail

_here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/_resources/lib.sh
. "$_here/../_resources/lib.sh"
cd "$(cv_repo_root)"
# shellcheck source=/dev/null
. ./digests.env   # $ZOT — same image as the live registry

work=$(mktemp -d)
cname="zot-retention-probe-$$"
cleanup() { docker rm -f "$cname" >/dev/null 2>&1 || true; rm -rf "$work"; }
trap cleanup EXIT

cat >"$work/config.json" <<'JSON'
{
  "storage": {
    "rootDirectory": "/var/lib/registry",
    "gc": true, "gcDelay": "2s", "gcInterval": "8s",
    "retention": {
      "dryRun": false,
      "policies": [
        { "repositories": ["evict-**"],
          "deleteReferrers": true, "deleteUntagged": true,
          "keepTags": [ { "patterns": [".*"], "pushedWithin": "5s" } ] },
        { "repositories": ["keep-**"],
          "deleteReferrers": true, "deleteUntagged": true,
          "keepTags": [ { "patterns": [".*"], "pushedWithin": "24h" } ] }
      ]
    }
  },
  "http": { "address": "0.0.0.0", "port": "5000" },
  "log": { "level": "info" }
}
JSON

docker run -d --name "$cname" -p 127.0.0.1:0:5000 \
	-v "$work/config.json":/etc/zot/config.json:ro \
	"ghcr.io/project-zot/zot-minimal-linux-arm64@${ZOT}" \
	serve /etc/zot/config.json >/dev/null
hp=$(docker port "$cname" 5000/tcp | head -1)
r=${hp/0.0.0.0/127.0.0.1}
tries=0
until curl -sf "http://${r}/v2/" >/dev/null 2>&1 || [ "$tries" -ge 40 ]; do
	tries=$((tries + 1))
	sleep 0.5
done

mk() { # $1 repo:tag  $2 content
	local d
	d=$(mktemp -d)
	printf '%s' "$2" >"$d/f"
	tar -C "$d" -cf "$d/l.tar" f
	crane append --oci-empty-base -f "$d/l.tar" -t "${r}/$1" >/dev/null 2>&1
	rm -rf "$d"
}
mk evict-aged:v1 "aged-$(date +%s%N)"
mk keep-fresh:v1 "fresh-$(date +%s%N)"
mk unmatched-repo:v1 "unmatched-$(date +%s%N)"

# window is 5s, gc interval 8s — one pass after ~15s has aged evict-aged out
sleep 20

repo_tags() {
	# A fully-evicted repo (evict-aged, once its only tag ages out) can 404 on
	# `crane ls` — that IS the expected "aged" outcome, not a script error.
	# `crane`'s own exit code is neutralized BEFORE the jq pipe so a 404 can't
	# poison it under `pipefail` (that previously produced a doubled "[]\n[]").
	local out
	out=$(crane ls "${r}/$1" 2>/dev/null || true)
	printf '%s' "$out" | jq -R . | jq -sc '[.[] | select(length > 0)]'
}
aged=$(repo_tags evict-aged)
fresh=$(repo_tags keep-fresh)
unmatched=$(repo_tags unmatched-repo)

delete_logged=false
if docker logs "$cname" 2>&1 | grep '"module":"retention"' \
	| jq -e 'select(.repository == "evict-aged" and .decision == "delete")' >/dev/null 2>&1; then
	delete_logged=true
fi

jq -nc \
	--argjson aged "$aged" --argjson fresh "$fresh" --argjson unmatched "$unmatched" \
	--argjson delete_logged "$delete_logged" \
	'{aged:$aged, fresh:$fresh, unmatched:$unmatched, delete_logged:$delete_logged}'
