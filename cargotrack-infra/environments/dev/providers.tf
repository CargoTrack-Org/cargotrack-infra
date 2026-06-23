provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Owner       = "cargotrack-team"
      ManagedBy   = "Terraform"
      Repository  = "CargoTrack-Org/cargotrack-infra"
    }
  }
}

# ACM certificates for CloudFront must be provisioned in us-east-1,
# regardless of the primary deployment region.
# This provider alias is used only by the dns module.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Owner       = "cargotrack-team"
      ManagedBy   = "Terraform"
      Repository  = "CargoTrack-Org/cargotrack-infra"
    }
  }
}

# ── EKS Helm + Kubernetes providers ───────────────────────────────────────────
#
# WHY exec instead of data sources:
#   data.aws_eks_cluster is evaluated at PLAN time, which fails on a fresh deploy
#   because the EKS cluster doesn't exist yet ("couldn't find resource").
#   Using `exec` with `aws eks get-token` defers token acquisition to APPLY time
#   (after the cluster is created by module.eks).
#
#   During plan:  module.eks.cluster_endpoint = (known after apply) → try() → ""
#                 No Kubernetes API calls are made during plan.
#   During apply: After module.eks creates the cluster, all K8s/Helm resources
#                 (which depend_on module.eks) use real credentials from exec.
#
# This is the correct one-apply pattern for EKS + Helm + Kubernetes in Terraform.

provider "helm" {
  kubernetes {
    host                   = try(module.eks.cluster_endpoint, "")
    cluster_ca_certificate = try(base64decode(module.eks.cluster_ca_data), "")
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # var.project_name is statically known at plan time (unlike module.eks.cluster_name
      # which is only known after apply). The cluster name = project_name by construction.
      args        = ["eks", "get-token", "--cluster-name", var.project_name, "--region", var.aws_region]
    }
  }
}

provider "kubernetes" {
  host                   = try(module.eks.cluster_endpoint, "")
  cluster_ca_certificate = try(base64decode(module.eks.cluster_ca_data), "")
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.project_name, "--region", var.aws_region]
  }
}

# ── kubectl provider (gavinbunney/kubectl) ────────────────────────────────────
# Used for ALL kubernetes_manifest resources (ClusterSecretStore, ExternalSecret,
# ArgoCD Application CRs).
#
# KEY DIFFERENCE from hashicorp/kubernetes_manifest:
#   kubernetes_manifest fetches CRD schemas from the API server AT PLAN TIME.
#   On a fresh deploy (cluster does not exist yet), this fails with:
#     "cannot create REST client: no client config"
#
#   kubectl_manifest defers all API communication to APPLY TIME, enabling the
#   one-apply pattern. During plan, it validates YAML structure locally only.
#
# load_config_file = false — prevents reading ~/.kube/config during plan,
#   which would fail in CI/CD or on a fresh machine.

provider "kubectl" {
  host                   = try(module.eks.cluster_endpoint, "")
  cluster_ca_certificate = try(base64decode(module.eks.cluster_ca_data), "")
  load_config_file       = false
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.project_name, "--region", var.aws_region]
  }
}
