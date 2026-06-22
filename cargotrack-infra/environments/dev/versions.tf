terraform {

  required_version = ">= 1.5"

  required_providers {

    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0, < 6.50"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }

    # Required by modules/eks to compute the OIDC issuer TLS thumbprint
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    # Helm provider — installs ALB Controller, Metrics Server, Cluster Autoscaler, ArgoCD
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }

    # Kubernetes provider — manages namespaces, secrets, and configmaps
    # NOTE: kubernetes_manifest is NOT used — it requires API connection at plan time.
    # CRD-based resources (ClusterSecretStore, ExternalSecret, ArgoCD Application)
    # use kubectl_manifest from gavinbunney/kubectl instead.
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }

    # kubectl provider — used for CRD-based kubernetes_manifest resources.
    # Key advantage over hashicorp/kubernetes_manifest: does NOT contact the
    # Kubernetes API server at plan time. All schema validation is deferred to
    # apply time, enabling the one-apply pattern on a fresh EKS cluster.
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }

    # Null provider — used for pre-destroy cleanup hooks (local-exec provisioners)
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
