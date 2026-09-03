output "flux_namespace" {
  description = "Namespace the Flux controllers run in."
  value       = "flux-system"
}

output "ocirepository" {
  description = "Flux OCIRepository the deploy task must publish artifacts for."
  value       = "${kubectl_manifest.cv_frontend_source.namespace}/${kubectl_manifest.cv_frontend_source.name}"
}

output "artifact_repo" {
  description = "OCI repo the deploy task pushes to (bare, no tag)."
  value       = var.zot_artifact_repo
}
