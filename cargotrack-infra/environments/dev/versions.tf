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

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
