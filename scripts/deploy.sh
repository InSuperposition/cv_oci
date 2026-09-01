#!/usr/bin/env bash
# deploy.sh <image-tag> <image-digest> <namespace> <app-sha> <pipelinerun>
#
# Deploy the release. Slice 1: OrbStack's `docker load` records no repo digest,
# so the Deployment references <image-tag> (which encodes the full APP_SHA)
# with imagePullPolicy: Never. <image-digest> is the crane-computed content
# digest — recorded in the cv-deploy-state ConfigMap and verified by the e2e
# test. Digest-ref deploy returns with a registry at Slice 3 (docs/debt.md).
#
# - applies the `cv` Deployment + Service
# - records the previous image ref, then waits for rollout
# - probes /healthz through the Service ("deployed" must mean "serving", 9e-A)
# - writes cv-deploy-state: current tag + digest, previous, app-sha,
#   pipelinerun, timestamp (rollback pointer, 1e-A / CQ3-A)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/log.sh
source "$HERE/lib/log.sh"
need kubectl
need curl

IMAGE="${1:-}"       # cv:git-<full-sha>
DIGEST="${2:-}"      # sha256:... (content digest, recorded not deployed)
NS="${3:-}"
APP_SHA="${4:-}"
PIPELINERUN="${5:-unknown}"
[ -n "$IMAGE" ] && [ -n "$DIGEST" ] && [ -n "$NS" ] && [ -n "$APP_SHA" ] \
	|| die "usage: deploy.sh <image-tag> <image-digest> <namespace> <app-sha> <pipelinerun>"

printf '%s' "$DIGEST" | grep -Eqx 'sha256:[0-9a-f]{64}' || die "deploy: bad image digest '$DIGEST'"

PORT="${APP_PORT:-44100}"
ROLLOUT_TIMEOUT="${DEPLOY_ROLLOUT_TIMEOUT:-120s}"
PULL_POLICY="${CV_IMAGE_PULL_POLICY:-Never}"

prev="$(kubectl -n "$NS" get deploy/cv -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo none)"
log_kv step=deploy prev="$prev" new="$IMAGE"

kubectl -n "$NS" apply -f - >/dev/null <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cv
  labels: { app: cv, app.kubernetes.io/part-of: cv-oci }
spec:
  replicas: 1
  selector: { matchLabels: { app: cv } }
  template:
    metadata: { labels: { app: cv } }
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
metadata: { name: cv, labels: { app: cv } }
spec:
  selector: { app: cv }
  ports: [{ port: 80, targetPort: $PORT }]
EOF

log_kv step=deploy action=wait-rollout timeout="$ROLLOUT_TIMEOUT"
if ! kubectl -n "$NS" rollout status deploy/cv --timeout="$ROLLOUT_TIMEOUT" >&2; then
	kubectl -n "$NS" describe deploy/cv >&2 || true
	die "deploy: rollout did not complete"
fi

url="http://cv.${NS}.svc.cluster.local/healthz"
code="$(curl -s -o /dev/null -m 15 -w '%{http_code}' "$url" || echo 000)"
[ "$code" = "200" ] || die "deploy: GET /healthz -> $code (want 200)"

kubectl -n "$NS" create configmap cv-deploy-state \
	--from-literal=current_tag="$IMAGE" \
	--from-literal=current_digest="$DIGEST" \
	--from-literal=previous="$prev" \
	--from-literal=app_sha="$APP_SHA" \
	--from-literal=pipelinerun="$PIPELINERUN" \
	--from-literal=updated="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
	--dry-run=client -o yaml | kubectl -n "$NS" apply -f - >/dev/null

log_kv step=deploy result=ok image="$IMAGE" digest="$DIGEST" healthz=200 app_sha="$APP_SHA"
