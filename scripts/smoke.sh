#!/usr/bin/env bash
# smoke.sh <image-ref> <namespace> [run-id] — prove the assembled image starts
# and serves /healthz on arm64, in isolation, before deploy touches the real
# Deployment.
#
# Creates a run-scoped Deployment + Service (imagePullPolicy: Never — the image
# is in the OrbStack store from assemble), waits for rollout, curls /healthz
# through the Service from this pod, then tears everything down. Teardown always
# runs (trap) — a failed smoke leaves nothing behind (2d-A).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/log.sh
source "$HERE/lib/log.sh"
need kubectl
need curl

IMAGE="${1:-}"
NS="${2:-}"
RUN_ID="${3:-$(date +%s)}"
[ -n "$IMAGE" ] && [ -n "$NS" ] || die "usage: smoke.sh <image-ref> <namespace> [run-id]"

NAME="cv-smoke-${RUN_ID}"
PORT="${APP_PORT:-44100}"
ROLLOUT_TIMEOUT="${SMOKE_ROLLOUT_TIMEOUT:-120s}"
CURL_MAX="${SMOKE_CURL_MAX:-15}"
# Never  — crane/apko path: the image is in the OrbStack store (docker load).
# IfNotPresent — CNB path: the image is a zot @sha256 ref, pulled by the kubelet.
PULL_POLICY="${CV_IMAGE_PULL_POLICY:-Never}"

cleanup() {
	kubectl -n "$NS" delete deploy,svc -l "cv-oci/smoke=$RUN_ID" --ignore-not-found --wait=false >/dev/null 2>&1 || true
	log_kv step=smoke action=teardown run_id="$RUN_ID"
}
trap cleanup EXIT

log_kv step=smoke action=create name="$NAME" image="$IMAGE"
kubectl -n "$NS" apply -f - >/dev/null <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $NAME
  labels: { cv-oci/smoke: "$RUN_ID" }
spec:
  replicas: 1
  selector: { matchLabels: { app: $NAME } }
  template:
    metadata: { labels: { app: $NAME, cv-oci/smoke: "$RUN_ID" } }
    spec:
      automountServiceAccountToken: false
      containers:
        - name: app
          image: $IMAGE
          imagePullPolicy: $PULL_POLICY
          env: [{ name: PORT, value: "$PORT" }]
          ports: [{ containerPort: $PORT }]
          readinessProbe:
            httpGet: { path: /healthz, port: $PORT }
            periodSeconds: 3
            failureThreshold: 20
          securityContext:
            runAsNonRoot: true
            allowPrivilegeEscalation: false
            capabilities: { drop: ["ALL"] }
            seccompProfile: { type: RuntimeDefault }
---
apiVersion: v1
kind: Service
metadata:
  name: $NAME
  labels: { cv-oci/smoke: "$RUN_ID" }
spec:
  selector: { app: $NAME }
  ports: [{ port: 80, targetPort: $PORT }]
EOF

log_kv step=smoke action=wait-rollout timeout="$ROLLOUT_TIMEOUT"
if ! kubectl -n "$NS" rollout status "deploy/$NAME" --timeout="$ROLLOUT_TIMEOUT" >&2; then
	kubectl -n "$NS" describe "deploy/$NAME" >&2 || true
	kubectl -n "$NS" logs "deploy/$NAME" --tail=40 >&2 || true
	die "smoke: rollout did not complete"
fi

url="http://${NAME}.${NS}.svc.cluster.local/healthz"
log_kv step=smoke action=probe url="$url"
code=000
for attempt in $(seq 1 10); do
	code="$(curl -s -o /dev/null -m "$CURL_MAX" -w '%{http_code}' "$url" 2>/dev/null || true)"
	[ "$code" = "200" ] && break
	log_kv step=smoke probe_attempt="$attempt" code="${code:-000}"
	sleep 3
done
if [ "$code" != "200" ]; then
	kubectl -n "$NS" get endpoints "$NAME" -o wide >&2 || true
	kubectl -n "$NS" get pods -l "app=$NAME" -o wide >&2 || true
	kubectl -n "$NS" logs "deploy/$NAME" --tail=30 >&2 || true
	die "smoke: GET /healthz -> ${code:-000} (want 200)"
fi

log_kv step=smoke result=ok image="$IMAGE" healthz=200
