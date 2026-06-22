# ── EKS outputs (used for kubectl config and Helm values injection) ───────────

output "eks_cluster_name" {
  description = "EKS cluster name — use with: aws eks update-kubeconfig --name <value>"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_oidc_issuer_url" {
  description = "OIDC issuer URL for IRSA verification"
  value       = module.eks.oidc_issuer_url
}

# ── IRSA role ARNs (inject into Helm values-dev.yaml for ServiceAccount annotations)

output "irsa_core_service_role_arn" {
  description = "IRSA role ARN for core-service — annotate ServiceAccount in Helm"
  value       = module.irsa.core_service_role_arn
}

output "irsa_document_service_role_arn" {
  description = "IRSA role ARN for document-service — annotate ServiceAccount in Helm"
  value       = module.irsa.document_service_role_arn
}

output "irsa_ai_service_role_arn" {
  description = "IRSA role ARN for ai-service — annotate ServiceAccount in Helm"
  value       = module.irsa.ai_service_role_arn
}

output "irsa_alb_controller_role_arn" {
  description = "IRSA role ARN for AWS Load Balancer Controller"
  value       = module.irsa.alb_controller_role_arn
}

output "irsa_cluster_autoscaler_role_arn" {
  description = "IRSA role ARN for Cluster Autoscaler (kube-system:cluster-autoscaler)"
  value       = module.irsa.cluster_autoscaler_role_arn
}

# ── AWS resource identifiers (used in Helm values for microservice env vars) ──

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = module.database.db_endpoint
  sensitive   = true
}

output "s3_bucket_name" {
  description = "S3 documents bucket name"
  value       = module.storage.bucket_id
}

output "event_bus_name" {
  description = "EventBridge custom event bus name"
  value       = module.eventing.event_bus_name
}

output "compliance_queue_url" {
  description = "SQS compliance trigger queue URL"
  value       = module.eventing.compliance_queue_url
}

output "dynamodb_audit_table" {
  description = "DynamoDB audit table name"
  value       = module.audit.table_name
}

output "kms_key_arn" {
  description = "KMS customer-managed key ARN"
  value       = module.database.kms_key_arn
  sensitive   = true
}

output "db_secret_arn" {
  description = "Database secrets ARN"
  value       = module.database.db_secret_arn
}

output "application_secret_arn" {
  description = "Application secrets (JWT and admin creds) ARN"
  value       = module.database.application_secret_arn
}

# CDN outputs — disabled while module.cdn is commented out
# Re-enable together with module.cdn in main.tf when domain_name is configured.
#
# output "cloudfront_domain_name" {
#   description = "CloudFront distribution domain — access the application at https://<value>"
#   value       = module.cdn.cloudfront_domain_name
# }
#
# output "cloudfront_distribution_id" {
#   description = "CloudFront distribution ID — use for cache invalidations"
#   value       = module.cdn.cloudfront_distribution_id
# }
#
# output "waf_web_acl_arn" {
#   description = "WAF Web ACL ARN attached to CloudFront"
#   value       = module.cdn.waf_web_acl_arn
# }

# ── ECR outputs ───────────────────────────────────────────────────────────────

output "ecr_repository_urls" {
  description = <<-EOT
    Map of service name → ECR repository URL.
    Use these as the image registry in Helm values files.
    Example: ecr_repository_urls["frontend"] = "<account>.dkr.ecr.<region>.amazonaws.com/cargotrack-frontend"
  EOT
  value       = module.ecr.repository_urls
}

output "ecr_registry_id" {
  description = "AWS account ID used as the ECR registry — needed for docker login"
  value       = module.ecr.registry_id
}

output "github_actions_ecr_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC ECR push — set as AWS_ECR_PUSH_ROLE_ARN in GitHub secrets"
  value       = module.ecr.github_actions_role_arn
}

# ── DNS outputs (populated only when domain_name is set) ─────────────────────

output "dns_name_servers" {
  description = "Route 53 NS records — configure at your domain registrar to complete DNS delegation (empty when domain_name is not set)"
  value       = module.dns.zone_name_servers
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN for CloudFront HTTPS (empty when domain_name is not set)"
  value       = module.dns.certificate_arn
}

output "dns_enabled" {
  description = "True when a domain was provided and DNS resources were created"
  value       = module.dns.dns_enabled
}

# ── Kubernetes platform outputs ───────────────────────────────────────────────

output "argocd_namespace" {
  description = "Namespace where ArgoCD is installed"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "cargotrack_dev_namespace" {
  description = "Dev namespace where CargoTrack dev pods run"
  value       = kubernetes_namespace.cargotrack_dev.metadata[0].name
}

output "cargotrack_prod_namespace" {
  description = "Prod namespace where CargoTrack prod pods run"
  value       = kubernetes_namespace.cargotrack_prod.metadata[0].name
}

output "eso_controller_version" {
  description = "Installed External Secrets Operator version"
  value       = helm_release.external_secrets.version
}

# GuardDuty outputs — disabled until training account permission is granted
# Uncomment together with module.guardduty in main.tf
# output "guardduty_detector_id" {
#   description = "AWS GuardDuty detector ID"
#   value       = module.guardduty.detector_id
# }
#
# output "guardduty_findings_rule_arn" {
#   description = "EventBridge rule ARN for high-severity GuardDuty findings"
#   value       = module.guardduty.findings_event_rule_arn
# }

output "irsa_eso_role_arn" {
  description = "IRSA role ARN for External Secrets Operator — annotated on the ESO Helm chart ServiceAccount"
  value       = module.irsa.eso_role_arn
}

output "ssm_path_prefix" {
  description = "SSM Parameter Store prefix for configuration"
  value       = "/cargotrack/"
}

output "platform_note" {
  description = "Post-apply steps required to complete GitOps bootstrap"
  value       = <<-EOT
    ── Post-apply steps ─────────────────────────────────────────────────────────
    1. Configure kubectl:
         aws eks update-kubeconfig --name <eks_cluster_name> --region us-east-1

    2. Get ArgoCD initial admin password:
         kubectl -n argocd get secret argocd-initial-admin-secret \
           -o jsonpath="{.data.password}" | base64 -d

    3. Verify dev + prod namespaces:
         kubectl get ns | grep cargotrack

    4. Verify ESO ClusterSecretStores are READY:
         kubectl get clustersecretstore

    5. Verify ExternalSecrets are READY (ESO synced to Secrets Manager):
         kubectl get externalsecret -n cargotrack-dev
         kubectl get externalsecret -n cargotrack-prod

    6. Verify ArgoCD Applications synced:
         kubectl get application -n argocd

    7. Once ArgoCD syncs and Ingress is created, get ALB DNS:
         kubectl get ingress -n cargotrack-dev
         kubectl get ingress -n cargotrack-prod

    8. GuardDuty detector is active — verify in AWS Console:
         Security > GuardDuty > Findings

    9. SSM Parameters are populated under /cargotrack/dev/:
         aws ssm get-parameters-by-path --path /cargotrack/dev/ --recursive
    ─────────────────────────────────────────────────────────────────────
  EOT
}

output "cargotrack_secrets_note" {
  description = "How cargotrack-secrets is managed — Terraform bootstrap + ESO live ownership"
  value       = <<-EOT
    BOOTSTRAP (apply day 0):
      Terraform creates kubernetes_secret 'cargotrack-secrets' in both
      cargotrack-dev and cargotrack-prod namespaces directly from AWS Secrets Manager.
      Pods start immediately — no ESO reconcile wait.

    LONG-TERM OWNERSHIP (after ESO reconciles, ~30s post-apply):
      ExternalSecret CRs (cargotrack-dev + cargotrack-prod) with creationPolicy=Merge
      take over synchronization. ESO reads Secrets Manager every 1h and updates the
      kubernetes_secret automatically. Secret rotation requires zero Terraform applies.

    DESTROY SAFETY:
      ExternalSecret CRs use deletionPolicy=Retain — ESO does not delete the K8s
      secret when its CR is removed. Terraform then deletes the kubernetes_secret.
      No double-delete race condition.

    Keys in cargotrack-secrets (both namespaces):
      DATABASE_PASSWORD  <- cargotrack-database-secret-v2  .password
      JWT_SECRET         <- cargotrack-application-secret-v2 .jwt_secret
      ADMIN_PASSWORD     <- cargotrack-application-secret-v2 .admin_password
  EOT
}

output "application_url" {
  description = "Primary application URL — https after DNS delegation, http ALB URL otherwise"
  value = (
    var.domain_name != "" ? "https://${var.domain_name}" :
    var.eks_ingress_alb_dns != "" ? "http://${var.eks_ingress_alb_dns}" :
    "ALB not yet known — run: kubectl get ingress -n cargotrack-dev -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'"
  )
}
