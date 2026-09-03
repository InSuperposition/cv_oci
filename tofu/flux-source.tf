# The cv-frontend deploy loop.
#
#   OCIRepository  cv-frontend  — tracks oci://<zot>/cv-frontend by semver,
#                                 verifies the Chains cosign signature, trusts
#                                 zot's self-signed CA. Never a mutable tag.
#   Kustomization  cv-frontend  — applies the verified artifact (prune on),
#                                 self-heals drift every kustomization_interval.
#
# The deploy task publishes a new version each verified build (CalVer, monotonic);
# spec.verify gates content regardless of tag, so a higher tag pointing at an old
# digest still fails to reconcile.

resource "kubectl_manifest" "cv_frontend_source" {
  depends_on = [
    kubectl_manifest.flux_components,
    kubernetes_secret.cosign_public_key,
    kubernetes_secret.zot_ca,
  ]

  yaml_body = yamlencode({
    apiVersion = "source.toolkit.fluxcd.io/v1"
    kind       = "OCIRepository"
    metadata = {
      name      = "cv-frontend"
      namespace = "flux-system"
      labels    = { "app.kubernetes.io/part-of" = "cv-oci" }
    }
    spec = {
      interval = var.source_interval
      url      = "oci://${var.zot_artifact_repo}"
      ref      = { semver = var.artifact_semver }
      # zot is HTTPS with a cert-manager self-signed CA — trust it explicitly,
      # do NOT set insecure (that is plain HTTP).
      certSecretRef = { name = kubernetes_secret.zot_ca.metadata[0].name }
      verify = {
        provider  = "cosign"
        secretRef = { name = kubernetes_secret.cosign_public_key.metadata[0].name }
      }
    }
  })
}

resource "kubectl_manifest" "cv_frontend_kustomization" {
  depends_on = [kubectl_manifest.cv_frontend_source]

  yaml_body = yamlencode({
    apiVersion = "kustomize.toolkit.fluxcd.io/v1"
    kind       = "Kustomization"
    metadata = {
      name      = "cv-frontend"
      namespace = "flux-system"
      labels    = { "app.kubernetes.io/part-of" = "cv-oci" }
    }
    spec = {
      interval        = var.kustomization_interval
      retryInterval   = "1m"
      path            = "./"
      prune           = true
      wait            = true
      timeout         = "3m"
      targetNamespace = var.app_namespace
      sourceRef = {
        kind = "OCIRepository"
        name = kubectl_manifest.cv_frontend_source.name
      }
    }
  })
}
