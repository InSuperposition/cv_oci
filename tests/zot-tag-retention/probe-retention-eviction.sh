#!/usr/bin/env bash
# probe-retention-eviction.sh — prove pushedWithin actually evicts aged tags,
# keeps in-window tags, and spares a repo matching no policy — against a
# throwaway zot container with a 5s window so the test does not wait 168h.
#
# Irreducible: this spins up a real zot (same pinned image as the live
# registry), pushes three tiny tags, waits one GC pass, and inspects what
# survived. No Kubernetes involved.
#
# T8a asserts in-script. T8b prints
#   {"aged":[...],"fresh":[...],"unmatched":[...],"delete_logged":bool}
# and a chainsaw assert: tree takes over.
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

aged=$(crane ls "${r}/evict-aged" 2>/dev/null | tr '\n' ' ' || true)
fresh=$(crane ls "${r}/keep-fresh" 2>/dev/null | tr '\n' ' ' || true)
unm=$(crane ls "${r}/unmatched-repo" 2>/dev/null | tr '\n' ' ' || true)
echo "after pass: evict-aged=[$aged] keep-fresh=[$fresh] unmatched-repo=[$unm]"

[ -z "$(printf '%s' "$aged" | tr -d '[:space:]')" ] \
	|| { echo "FAIL: aged tag was NOT evicted (evict-aged=[$aged])" >&2; exit 1; }
printf '%s' "$fresh" | grep -qw v1 \
	|| { echo "FAIL: in-window tag keep-fresh:v1 was evicted" >&2; exit 1; }
printf '%s' "$unm" | grep -qw v1 \
	|| { echo "FAIL: unmatched-repo:v1 was evicted (no policy should have matched it)" >&2; exit 1; }

docker logs "$cname" 2>&1 | grep '"module":"retention"' \
	| jq -e 'select(.repository == "evict-aged" and .decision == "delete")' >/dev/null \
	|| { echo "FAIL: no retention delete decision logged for evict-aged" >&2; exit 1; }
