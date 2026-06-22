# \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
# CargoTrack v3 \u2014 Dev Environment
# Migrated from EC2/ASG \u2192 EKS microservices architecture
# \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

# ── NETWORKING ────────────────────────────────────────────────────────────────
# VPC, 8 subnets (public/web/app/db), NAT gateway, route tables
# Now includes EKS subnet discovery tags (kubernetes.io/role/*)

module "networking" {

  source = "../../modules/networking"

  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
}

# ── SECURITY ──────────────────────────────────────────────────────────────────
# Security groups for all tiers including new eks_node SG
# database SG now allows connections from eks_node SG (port 5432)

module "security" {

  source = "../../modules/security"

  project_name = var.project_name

  vpc_id = module.networking.vpc_id
}

# ── DATABASE ─────────────────────────────────────────────────────────────────
# RDS PostgreSQL, KMS key, Secrets Manager secrets, SSM parameters
# Unchanged from v2 — fully decoupled from compute model

module "database" {

  source = "../../modules/database"

  project_name = var.project_name

  db_subnet_ids = module.networking.db_subnet_ids

  database_sg_id = module.security.database_sg_id
}

# ── STORAGE ───────────────────────────────────────────────────────────────────
# S3 document bucket with KMS encryption, versioning, lifecycle rules
# Unchanged from v2

module "storage" {

  source = "../../modules/storage"

  project_name = var.project_name

  kms_key_arn = module.database.kms_key_arn
}

# ── AUDIT ─────────────────────────────────────────────────────────────────────
# DynamoDB audit table — stores compliance and shipment event records
# Unchanged from v2

module "audit" {

  source = "../../modules/audit"

  project_name = var.project_name
  kms_key_arn  = module.database.kms_key_arn
}

# ── EVENTING ─────────────────────────────────────────────────────────────────
# EventBridge custom bus, SQS queues (main + compliance DLQ/queue),
# Lambda document processor, EventBridge rules
# Phase 3 compliance queue additions included

module "eventing" {

  source = "../../modules/eventing"

  project_name = var.project_name
  aws_region   = var.aws_region

  kms_key_arn      = module.database.kms_key_arn
  audit_table_name = module.audit.table_name
  audit_table_arn  = module.audit.table_arn
}

# ── MONITORING ────────────────────────────────────────────────────────────────
# SNS alarms topic, CloudWatch alarms, dashboard
# ASG/ALB-specific alarms omitted (vars default to "" \u2014 handled in module)
# RDS alarm always active

module "monitoring" {

  source = "../../modules/monitoring"

  project_name = var.project_name
  aws_region   = var.aws_region

  # EC2/ASG references removed — module will skip those alarms
  # backend_asg_name        = (not set — defaults to "")
  # external_alb_arn_suffix = (not set — defaults to "")

  db_identifier = module.database.db_identifier
  alarm_email   = var.alarm_email
  kms_key_arn   = module.database.kms_key_arn

  # EKS Container Insights alarms — enabled now that EKS is the compute platform
  eks_cluster_name = module.eks.cluster_name

  # SQS compliance queue depth alarm — reuses existing queue name from eventing module
  compliance_queue_name = module.eventing.compliance_queue_name
}

# ── VPC ENDPOINTS ────────────────────────────────────────────────────────────
# Private connectivity to AWS services (S3 Gateway, SSM, Secrets Manager, KMS)
# Endpoints SG updated to allow from eks_node SG

module "endpoints" {

  source = "../../modules/endpoints"

  project_name   = var.project_name
  vpc_id         = module.networking.vpc_id
  aws_region     = var.aws_region
  app_subnet_ids = module.networking.app_subnet_ids
  backend_sg_id  = module.security.eks_node_sg_id # eks_node replaces old backend SG here

  private_route_table_ids = [
    module.networking.web_route_table_id,
    module.networking.app_route_table_id,
    module.networking.db_route_table_id,
  ]
}

# ── CDN ───────────────────────────────────────────────────────────────────────
# CloudFront + WAF v2.
#
# Dependency order:
#   1. module.dns  → creates ACM cert (us-east-1) + validates it via Route53
#   2. module.cdn  → creates CloudFront, using the validated ACM cert ARN
#   3. aws_route53_record (below) → A-records pointing to the CF domain
#
# Why A-records are at env level (not inside module.dns):
#   If A-records were inside dns, dns would depend on cdn (for cf domain name)
#   AND cdn would depend on dns (for cert ARN) → circular dependency.
#   Moving A-records to env level gives both outputs without a cycle.

module "cdn" {

  source = "../../modules/cdn"

  project_name = var.project_name

  # ALB DNS is baked into the variable default — no manual -var needed.
  alb_dns_name = var.eks_ingress_alb_dns

  # Pass the validated ACM cert from the dns module.
  # When domain_name = "", dns.certificate_arn = "" and CF uses its default cert.
  acm_certificate_arn = module.dns.certificate_arn

  # CloudFront aliases must exactly match the ACM cert's domain names.
  domain_aliases = var.domain_name != "" ? [var.domain_name, "www.${var.domain_name}"] : []

  # dns module must complete (cert validated) before CF is created with the cert.
  depends_on = [module.dns]
}

# ── DNS (Route53 + ACM) ───────────────────────────────────────────────────────
# Conditional on domain_name being set. All resources inside use count = 0
# when domain_name = "", so this is completely safe to always include.
# The cloudfront_domain_name variable is removed from this module — A-records
# now live at environment level (see aws_route53_record blocks below).

module "dns" {

  source = "../../modules/dns"

  project_name = var.project_name
  domain_name  = var.domain_name

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

# ── Route 53 A-records → CloudFront ──────────────────────────────────────────
# These live at environment level (not inside module.dns) to break the
# circular dependency: module.cdn needs dns.certificate_arn, and the A-records
# need cdn.cloudfront_domain_name. Placing both in the same module would create
# a cycle. At env level, all outputs are available without any cycle.

resource "aws_route53_record" "cloudfront_apex" {
  count = var.domain_name != "" ? 1 : 0

  zone_id = module.dns.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = module.cdn.cloudfront_domain_name
    zone_id                = "Z2FDTNDATAQYW2" # CloudFront global zone ID (constant)
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "cloudfront_www" {
  count = var.domain_name != "" ? 1 : 0

  zone_id = module.dns.zone_id
  name    = "www.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [module.cdn.cloudfront_domain_name]
}

# EKS control plane + managed node group + OIDC provider for IRSA
# Replaces the EC2/ASG-based compute module

module "eks" {

  source = "../../modules/eks"

  project_name   = var.project_name
  vpc_id         = module.networking.vpc_id
  app_subnet_ids = module.networking.app_subnet_ids
  node_sg_id     = module.security.eks_node_sg_id

  cluster_version     = var.eks_cluster_version
  node_instance_types = var.node_instance_types
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_desired_size   = var.node_desired_size
}

# ── RDS ingress from EKS worker nodes ─────────────────────────────────────────
#
# WHY THIS IS AT THE ENVIRONMENT LEVEL (not inside module.security):
#
#   EKS managed node groups receive security groups from TWO sources:
#
#   1. cargotrack-eks_node-sg  (Terraform-managed, created by module.security)
#      Passed to aws_eks_cluster.vpc_config.security_group_ids.
#      AWS attaches this to CONTROL PLANE ENIs only — the cross-account ENIs
#      EKS creates in your VPC to enable cluster-to-node communication.
#      Worker node EC2 instances do NOT carry this SG.
#
#   2. eks-cluster-sg-cargotrack-* (auto-created by AWS at cluster creation time)
#      Exposed as: aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
#      module.eks output: module.eks.cluster_sg_id
#      AWS automatically attaches this to EVERY managed node ENI. This is the
#      SG that controls actual inbound/outbound traffic on the worker nodes.
#
#   Consequence: Any RDS ingress rule that references cargotrack-eks_node-sg (#1)
#   has NO effect because the worker nodes never carry that SG. The previous rule
#   `database_from_eks_node` in module.security was wrong — it referenced #1.
#
# WHY IT CANNOT LIVE IN module.security:
#   module.security is instantiated before module.eks (EKS needs the eks_node SG).
#   cluster_sg_id (#2) is only known after the EKS cluster is created.
#   Putting this rule inside module.security would create a circular dependency.
#
#   At the environment level, both outputs are available with no cycle:
#     module.security.database_sg_id  ← security group to protect (RDS)
#     module.eks.cluster_sg_id        ← source of the traffic (worker nodes)
#
# DESTROY SAFETY:
#   Terraform destroys this rule before either module (dependency graph reversal).
#   No dangling SG rules after destroy.

resource "aws_vpc_security_group_ingress_rule" "database_from_cluster_sg" {

  security_group_id            = module.security.database_sg_id
  referenced_security_group_id = module.eks.cluster_sg_id

  from_port   = 5432
  to_port     = 5432
  ip_protocol = "tcp"

  tags = {
    Name      = "cargotrack-rds-from-eks-cluster-sg"
    ManagedBy = "Terraform"
    Purpose   = "Allow EKS worker nodes to reach RDS PostgreSQL on port 5432"
  }
}



# ── IRSA (IAM Roles for Service Accounts) ─────────────────────────────────────
# Per-service IAM roles scoped to exact Kubernetes service account names.
# Each microservice gets only the permissions it needs (least privilege).
# Role ARNs are passed into Helm values for ServiceAccount annotations.

module "irsa" {

  source = "../../modules/irsa"

  project_name      = var.project_name
  oidc_issuer_url   = module.eks.oidc_issuer_url
  oidc_provider_arn = module.eks.oidc_provider_arn
  cluster_name      = module.eks.cluster_name
  aws_region        = var.aws_region

  documents_bucket_arn = module.storage.bucket_arn
  event_bus_arn        = module.eventing.event_bus_arn
  compliance_queue_arn = module.eventing.compliance_queue_arn
  audit_table_arn      = module.audit.table_arn
  kms_key_arn          = module.database.kms_key_arn
  db_secret_arn        = module.database.db_secret_arn
  app_secret_arn       = module.database.application_secret_arn
}

# ──────────────────────────────────────────────────────────────────────────────
# CargoTrack v3 — Dev Environment
# Migrated from EC2/ASG → EKS microservices architecture
# CI/CD managed by GitHub Actions (see .github/workflows/infra.yml)
# ──────────────────────────────────────────────────────────────────────────────

# Images must be pushed before pods can be scheduled (CI/CD responsibility).

module "ecr" {

  source = "../../modules/ecr"

  project_name      = var.project_name
  eks_node_role_arn = module.eks.node_role_arn
}

# ── GUARDDUTY — TEMPORARILY DISABLED ─────────────────────────────────────────
# GuardDuty requires explicit permission in the training account.
# Re-enable by uncommenting the block below once permission is granted.
# Threat detection: CloudTrail analysis, VPC Flow Logs, EKS audit logs,
# S3 data protection, malware scanning on EKS workloads.
# HIGH/CRITICAL findings (severity >= 7) route to SNS → email if alarm_email is set.

# module "guardduty" {
#   source       = "../../modules/guardduty"
#   project_name = var.project_name
#   alarm_email  = var.alarm_email
#   kms_key_arn  = module.database.kms_key_arn
# }

# ── SSM PARAMETER STORE — Operational Configuration ──────────────────────────
#
# DESIGN RATIONALE:
#   All non-sensitive operational configuration is stored in SSM Parameter Store.
#   This provides:
#   - Centralized config management (no hardcoded values in Kubernetes manifests)
#   - Audit trail (CloudTrail tracks all GetParameter calls)
#   - IAM-scoped access (ESO and services read /cargotrack/* only)
#   - Change management (config changes visible in SSM console, not just Terraform state)
#   - Future readiness (services can read config directly via SSM SDK if needed)
#
# SENSITIVE VALUES are NOT stored here. Database password, JWT secret, and admin
# password remain in AWS Secrets Manager (module.database) and are synced to
# Kubernetes via ESO ExternalSecret → kubernetes_secret.
#
# HIERARCHY: /cargotrack/{environment}/{category}/{key}
# ESO's IRSA policy grants ssm:GetParameter on arn:...:parameter/cargotrack/*

resource "aws_ssm_parameter" "db_host" {
  name  = "/cargotrack/${var.environment}/database/host"
  type  = "String"
  value = split(":", module.database.db_endpoint)[0]

  description = "CargoTrack RDS PostgreSQL hostname (port stripped)"
  tags = {
    Category = "database"
    Service  = "rds"
  }
}

resource "aws_ssm_parameter" "db_port" {
  name  = "/cargotrack/${var.environment}/database/port"
  type  = "String"
  value = "5432"

  description = "CargoTrack RDS PostgreSQL port"
  tags = {
    Category = "database"
    Service  = "rds"
  }
}

resource "aws_ssm_parameter" "db_name" {
  name  = "/cargotrack/${var.environment}/database/name"
  type  = "String"
  value = "cargotrack"

  description = "CargoTrack PostgreSQL database name"
  tags = {
    Category = "database"
    Service  = "rds"
  }
}

resource "aws_ssm_parameter" "db_user" {
  name  = "/cargotrack/${var.environment}/database/user"
  type  = "String"
  value = "cargotrack"

  description = "CargoTrack PostgreSQL database username (non-sensitive)"
  tags = {
    Category = "database"
    Service  = "rds"
  }
}

resource "aws_ssm_parameter" "aws_region" {
  name  = "/cargotrack/${var.environment}/aws/region"
  type  = "String"
  value = var.aws_region

  description = "AWS region for CargoTrack services"
  tags = {
    Category = "aws"
  }
}

resource "aws_ssm_parameter" "s3_bucket" {
  name  = "/cargotrack/${var.environment}/s3/bucket-name"
  type  = "String"
  value = module.storage.bucket_id

  description = "CargoTrack S3 documents bucket name"
  tags = {
    Category = "storage"
    Service  = "s3"
  }
}

resource "aws_ssm_parameter" "event_bus_name" {
  name  = "/cargotrack/${var.environment}/eventbridge/event-bus-name"
  type  = "String"
  value = module.eventing.event_bus_name

  description = "CargoTrack EventBridge custom event bus name"
  tags = {
    Category = "eventing"
    Service  = "eventbridge"
  }
}

resource "aws_ssm_parameter" "compliance_queue_url" {
  name  = "/cargotrack/${var.environment}/sqs/compliance-queue-url"
  type  = "String"
  value = module.eventing.compliance_queue_url

  description = "SQS compliance trigger queue URL (consumed by ai-service)"
  tags = {
    Category = "eventing"
    Service  = "sqs"
  }
}

resource "aws_ssm_parameter" "audit_table_name" {
  name  = "/cargotrack/${var.environment}/dynamodb/audit-table"
  type  = "String"
  value = module.audit.table_name

  description = "DynamoDB audit trail table name"
  tags = {
    Category = "database"
    Service  = "dynamodb"
  }
}

resource "aws_ssm_parameter" "db_secret_arn" {
  name  = "/cargotrack/${var.environment}/secrets/db-secret-arn"
  type  = "String"
  value = module.database.db_secret_arn

  description = "ARN of the Secrets Manager secret for RDS credentials (for application self-discovery)"
  tags = {
    Category = "secrets"
    Service  = "secretsmanager"
  }
}

resource "aws_ssm_parameter" "app_secret_arn" {
  name  = "/cargotrack/${var.environment}/secrets/app-secret-arn"
  type  = "String"
  value = module.database.application_secret_arn

  description = "ARN of the Secrets Manager secret for app credentials (JWT, admin)"
  tags = {
    Category = "secrets"
    Service  = "secretsmanager"
  }
}

