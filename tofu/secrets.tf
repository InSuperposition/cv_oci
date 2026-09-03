# Seed Secrets for Flux, copied off the live cluster — never committed.
#
#   cosign-public-key : the Tekton Chains signing public key. source-controller
#                       gates the OCIRepository reconcile against it
#                       (spec.verify.provider = cosign).
#   zot-ca            : zot's self-signed serving CA. source-controller mounts
#                       it (spec.certSecretRef) to trust zot over TLS.
#
# Once cv_openbao exists these move to a kv entry synced by the OpenBao Secrets
# Operator (debt row in the design doc).

data "kubernetes_secret" "chains_signing" {
  metadata {
    name      = "signing-secrets"
    namespace = var.chains_namespace
  }
}

data "kubernetes_secret" "zot_tls" {
  metadata {
    name      = "zot-tls"
    namespace = var.app_namespace
  }
}

resource "kubernetes_secret" "cosign_public_key" {
  metadata {
    name      = "cosign-public-key"
    namespace = "flux-system"
    labels = {
      "app.kubernetes.io/part-of"   = "cv-oci"
      "app.kubernetes.io/component" = "flux-verification"
    }
  }
  # source-controller's cosign verifier expects a `.pub`-suffixed key.
  data = {
    "cosign.pub" = data.kubernetes_secret.chains_signing.data["cosign.pub"]
  }

  depends_on = [kubectl_manifest.flux_components]
}

resource "kubernetes_secret" "zot_ca" {
  metadata {
    name      = "zot-ca"
    namespace = "flux-system"
    labels = {
      "app.kubernetes.io/part-of"   = "cv-oci"
      "app.kubernetes.io/component" = "flux-verification"
    }
  }
  data = {
    "ca.crt" = data.kubernetes_secret.zot_tls.data["ca.crt"]
  }

  depends_on = [kubectl_manifest.flux_components]
}
