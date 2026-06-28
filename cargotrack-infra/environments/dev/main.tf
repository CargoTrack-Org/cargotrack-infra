module "networking" {

  source = "../../modules/networking"

  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
}

module "security" {

  source = "../../modules/security"

  project_name = var.project_name

  vpc_id = module.networking.vpc_id
}

module "database" {

  source = "../../modules/database"

  project_name = var.project_name

  db_subnet_ids = module.networking.db_subnet_ids

  database_sg_id = module.security.database_sg_id
}

module "storage" {

  source = "../../modules/storage"

  project_name = var.project_name

  kms_key_arn = module.database.kms_key_arn
}

module "audit" {

  source = "../../modules/audit"

  project_name = var.project_name
  kms_key_arn  = module.database.kms_key_arn
}

module "eventing" {

  source = "../../modules/eventing"

  project_name = var.project_name
  aws_region   = var.aws_region

  kms_key_arn      = module.database.kms_key_arn
  audit_table_name = module.audit.table_name
  audit_table_arn  = module.audit.table_arn
}

module "monitoring" {

  source = "../../modules/monitoring"

  project_name = var.project_name
  aws_region   = var.aws_region

  db_identifier = module.database.db_identifier
  alarm_email   = var.alarm_email
  kms_key_arn   = module.database.kms_key_arn

  eks_cluster_name = var.project_name

  compliance_queue_name = "${var.project_name}-compliance-trigger"
}

module "endpoints" {

  source = "../../modules/endpoints"

  project_name   = var.project_name
  vpc_id         = module.networking.vpc_id
  aws_region     = var.aws_region
  app_subnet_ids = module.networking.app_subnet_ids
  backend_sg_id  = module.security.eks_node_sg_id

  private_route_table_ids = [
    module.networking.web_route_table_id,
    module.networking.app_route_table_id,
    module.networking.db_route_table_id,
  ]
}

module "cdn" {

  source = "../../modules/cdn"

  project_name = var.project_name

  alb_dns_name = var.eks_ingress_alb_dns

  acm_certificate_arn = module.dns.certificate_arn

  domain_aliases = var.domain_name != "" ? [var.domain_name, "www.${var.domain_name}", "dev.${var.domain_name}"] : []

  depends_on = [module.dns]
}


module "dns" {

  source = "../../modules/dns"

  project_name = var.project_name
  domain_name  = var.domain_name

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

resource "aws_route53_record" "cloudfront_apex" {
  count   = var.domain_name != "" ? 1 : 0
  zone_id = module.dns.zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = module.cdn.cloudfront_domain_name
    zone_id                = "Z2FDTNDATAQYW2"
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "cloudfront_www" {
  count   = var.domain_name != "" ? 1 : 0
  zone_id = module.dns.zone_id
  name    = "www.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [module.cdn.cloudfront_domain_name]
}

resource "aws_route53_record" "cloudfront_dev" {
  count   = var.domain_name != "" ? 1 : 0
  zone_id = module.dns.zone_id
  name    = "dev.${var.domain_name}"
  type    = "A"
  alias {
    name                   = module.cdn.cloudfront_domain_name
    zone_id                = "Z2FDTNDATAQYW2"
    evaluate_target_health = false
  }
}

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

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_cluster_sg" {

  security_group_id            = module.endpoints.endpoints_security_group_id
  referenced_security_group_id = module.eks.cluster_sg_id

  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  tags = {
    Name      = "cargotrack-endpoints-from-eks-cluster-sg"
    ManagedBy = "Terraform"
    Purpose   = "Allow EKS worker node pods to reach VPC endpoints (Secrets Manager, SSM, KMS, S3) on port 443"
  }
}



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

module "ecr" {

  source = "../../modules/ecr"

  project_name      = var.project_name
  eks_node_role_arn = module.eks.node_role_arn
}

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
