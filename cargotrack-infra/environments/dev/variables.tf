variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name — used as prefix for all resource names"
  type        = string
  default     = "cargotrack"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod) — used for resource tagging"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "alarm_email" {
  description = "Email address for CloudWatch alarm SNS notifications"
  type        = string
  # Set to project team email — SNS subscription is created and pending confirmation.
  # Change to null to disable email alerts.
  default     = "abhibee27@gmail.com"
}

# ─── EKS variables ────────────────────────────────────────────────────────────

variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.30"
}

variable "node_instance_types" {
  description = "EC2 instance types for EKS worker nodes"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_min_size" {
  description = "Minimum number of EKS worker nodes"
  type        = number
  # 2 nodes minimum for high-availability (dev and prod namespaces share cluster)
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of EKS worker nodes"
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 2
}

variable "eks_ingress_alb_dns" {
  description = <<-EOT
    DNS name of the ALB created by the AWS Load Balancer Controller after Helm/ArgoCD deploys the Ingress.
    Leave empty on first apply — get the value after apply with:
      kubectl get ingress -n cargotrack-dev -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
  EOT
  type    = string
  # Dev ALB created by AWS LBC for cargotrack-dev ingress (kubectl get ingress -n cargotrack-dev)
  default = "k8s-cargotra-cargotra-78a37b4796-321169976.us-east-1.elb.amazonaws.com"
}

# ─── GitHub OIDC ──────────────────────────────────────────────────────────────

variable "github_repository" {
  description = "GitHub repository in OrgName/RepoName format — scopes the GitHub Actions OIDC trust policy to this repo only"
  type        = string
  default     = "CargoTrack-Org/cargotrack-app"
}

variable "domain_name" {
  description = <<-EOT
    Custom domain name for the CargoTrack platform.
    Set to "" to skip Route 53, ACM, and custom CloudFront certificate.
    When set, the dns module creates a hosted zone + ACM cert (us-east-1),
    and the cdn module uses the cert for HTTPS with a proper TLS certificate.

    After terraform apply, copy the NS records from the Terraform output
    (dns_name_servers) to your domain registrar to complete DNS delegation.
  EOT
  type    = string
  # ── Domain is now configured — enables Route53 + ACM + CloudFront HTTPS ──
  default = "shopp-novaa.co.in"
}