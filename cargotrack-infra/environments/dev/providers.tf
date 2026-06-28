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

provider "helm" {
  kubernetes {
    host                   = try(module.eks.cluster_endpoint, "")
    cluster_ca_certificate = try(base64decode(module.eks.cluster_ca_data), "")
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
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
