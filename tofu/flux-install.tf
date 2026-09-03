# Flux CD install — source-controller + kustomize-controller only.
#
# The manifest set is vendored + digest-pinned in tofu/flux/components.yaml
# (see the header there for the re-vendor procedure). This is the chicken-egg
# boundary: tofu installs Flux, then Flux reconciles the cv-frontend app.
# bootstrap.sh stays frozen at the pre-Flux layer.

data "kubectl_file_documents" "flux_components" {
  content = file("${path.module}/flux/components.yaml")
}

resource "kubectl_manifest" "flux_components" {
  for_each  = data.kubectl_file_documents.flux_components.manifests
  yaml_body = each.value

  server_side_apply = true
  # CRDs must settle before the Flux CRs in flux-source.tf apply; the CRs carry
  # an explicit depends_on, and the provider retries transient races.
  wait = true
}
