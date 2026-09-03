provider "kubectl" {
  config_path       = pathexpand(var.kubeconfig_path)
  config_context    = var.kube_context
  apply_retry_count = 3
  # Server-side apply: CRDs and the CRs that use them can live in one apply.
  load_config_file = true
}

provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = var.kube_context
}
