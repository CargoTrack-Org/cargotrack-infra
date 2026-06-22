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
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}

provider "kubernetes" {
  host                   = try(module.eks.cluster_endpoint, "")
  cluster_ca_certificate = try(base64decode(module.eks.cluster_ca_data), "")
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}
