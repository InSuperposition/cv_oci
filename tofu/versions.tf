terraform {
  required_version = ">= 1.9"

  required_providers {
    # Raw multi-document manifest apply (Flux components.yaml + the Flux CRs).
    # alekc/kubectl is the maintained fork of gavinbunney/kubectl; it applies
    # documents server-side without needing the target CRDs to exist at plan
    # time, which the hashicorp kubernetes_manifest resource does require.
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
    # Reading the seed Secrets (cosign public key, zot CA) off the live cluster.
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
  }
}
