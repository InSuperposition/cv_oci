variable "kube_context" {
  description = "kubeconfig context to provision against."
  type        = string
  default     = "orbstack"
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file."
  type        = string
  default     = "~/.kube/config"
}

variable "app_namespace" {
  description = "Namespace the cv-frontend app is reconciled into."
  type        = string
  default     = "cv-pipeline"
}

variable "chains_namespace" {
  description = "Namespace holding the Tekton Chains signing-secrets Secret."
  type        = string
  default     = "tekton-chains"
}

variable "zot_artifact_repo" {
  description = "OCI repository (no scheme, no tag) the deploy task pushes the rendered manifest artifact to, and source-controller reconciles from."
  type        = string
  default     = "zot.cv-pipeline.svc.cluster.local:5000/cv-frontend"
}

variable "artifact_semver" {
  description = "Semver range the OCIRepository resolves. '>=0.0.0' takes the highest published version; never a mutable tag."
  type        = string
  default     = ">=0.0.0"
}

variable "source_interval" {
  description = "OCIRepository poll interval. Short enough that an async Chains signature is picked up quickly (P12)."
  type        = string
  default     = "1m"
}

variable "kustomization_interval" {
  description = "Kustomization reconcile interval — drift correction cadence."
  type        = string
  default     = "5m"
}
