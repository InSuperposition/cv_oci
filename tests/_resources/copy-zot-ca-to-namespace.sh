#!/usr/bin/env bash
# copy-zot-ca-to-namespace.sh <namespace> — copy the zot-tls CA cert from
# cv-pipeline into <namespace> as a `zot-tls` secret holding just ca.crt.
#
# The deploy task's `flux push artifact` step mounts ca.crt from this secret
# (SSL_CERT_FILE) to reach zot over TLS. An ephemeral test namespace needs its
# own copy.
#
# Idempotent (apply, not create). Prints {"namespace":..,"secret":"zot-tls"}.
set -euo pipefail

ns=${1:?usage: copy-zot-ca-to-namespace.sh <namespace>}

ca=$(kubectl get secret zot-tls -n cv-pipeline -o jsonpath='{.data.ca\.crt}' | base64 -d)
kubectl create secret generic zot-tls -n "$ns" \
	--from-literal=ca.crt="$ca" \
	--dry-run=client -o yaml | kubectl apply -n "$ns" -f - >/dev/null

jq -nc --arg ns "$ns" '{namespace: $ns, secret: "zot-tls"}'
