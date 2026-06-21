# CargoTrack Infra

Terraform infrastructure as code for the CargoTrack Logistics Platform on AWS EKS.

## Repository Structure

```
cargotrack-infra/
├── bootstrap/              # S3 state bucket + DynamoDB lock table (run once)
├── environments/
│   └── dev/                # Dev environment (main.tf, k8s.tf, variables.tf, terraform.tfvars)
└── modules/
    ├── networking/          # VPC, subnets, NAT gateway, route tables
    ├── security/            # Security groups (EKS nodes, RDS, ALB)
    ├── eks/                 # EKS cluster, managed node group, OIDC provider
    ├── database/            # RDS PostgreSQL, KMS, Secrets Manager
    ├── storage/             # S3 document bucket
    ├── audit/               # DynamoDB audit trail
    ├── eventing/            # EventBridge, SQS, Lambda
    ├── irsa/                # IAM roles for service accounts (per-microservice)
    ├── ecr/                 # ECR repositories + GitHub OIDC push role
    ├── monitoring/          # CloudWatch log groups, alarms, SNS, dashboard
    ├── endpoints/           # VPC endpoints (S3, Secrets Manager, KMS, SSM)
    ├── cdn/                 # CloudFront + WAF
    └── dns/                 # Route53 + ACM
```

## CI/CD Flow

```
Push to main (terraform/ changes)
  → terraform-apply.yml: tfsec scan → terraform validate → terraform plan
  → Manual approval gate (GitHub Environment: production)
  → terraform apply
```

## Required GitHub Secrets

| Secret | Description |
|---|---|
| `AWS_INFRA_ROLE_ARN` | IAM role ARN with AdministratorAccess for terraform apply |

## State Backend

Remote state is stored in S3 with DynamoDB locking.
See `cargotrack-infra/bootstrap/` for initial setup.
