# =============================================================================
# k8s.tf — Kubernetes platform layer
#
# Apply order (enforced via depends_on):
#   1.  Namespaces (argocd, cargotrack-dev, cargotrack-prod)
#   2.  AWS Load Balancer Controller  — kube-system  (needs nodes + IRSA)
#   3.  Metrics Server                — kube-system  (needed for HPA)
#   4.  Cluster Autoscaler            — kube-system  (least-waste expander)
#   5.  Bootstrap K8s Secrets         — cargotrack-dev + cargotrack-prod
#       (Terraform-injected from Secrets Manager — ensures pods start on first apply)
#   6.  Bootstrap ConfigMaps          — cargotrack-dev + cargotrack-prod
#       (Terraform-injected with RDS/SQS/S3 values — no ArgoCD dependency)
#   7.  ArgoCD                        — argocd        (depends on LBC for NLB)
#   8.  External Secrets Operator     — external-secrets (wait=true)
#   9.  ClusterSecretStore CRs        — (after ESO CRDs are installed)
#   10. ExternalSecret CRs            — cargotrack-dev + cargotrack-prod
#       (ESO reads Secrets Manager, merges into bootstrap secrets)
#   11. null_resource pre-destroy     — (no-op on apply; cleans Ingress on destroy)
#   12. cargotrack-dev ArgoCD App CR  — argocd (IRSA ARNs injected by Terraform)
#   13. cargotrack-prod ArgoCD App CR — argocd (IRSA ARNs injected by Terraform)
#   14. ArgoCD root-app CR            — argocd (app-of-apps, no finalizer)
#
# Destroy order (reversed dependency graph):
#   root-app → prod-app → dev-app → null_resource (ingress cleanup dev+prod)
#   → ExternalSecret CRs → ClusterSecretStores → ESO Helm
#   → ArgoCD Helm → Bootstrap Secrets + ConfigMaps → Namespaces
#   → LBC + Metrics + Autoscaler → EKS Node Group → EKS Cluster
#
# ESO Bootstrap Pattern (one-apply guarantee):
#   kubernetes_secret (bootstrap) created by Terraform with current SM values.
#   ExternalSecret CR with creationPolicy=Merge takes ownership after ESO installs.
#   ESO syncs live values from Secrets Manager → updates the bootstrap secret.
#   On destroy: ExternalSecret (deletionPolicy=Retain) is deleted first by Terraform,
#   then kubernetes_secret is deleted by Terraform. No orphaned resources.
#
# Dev/Prod Namespace Architecture:
#   Single EKS cluster. Two namespaces: cargotrack-dev and cargotrack-prod.
#   Each namespace has its own:
#     - Bootstrap secret (kubernetes_secret)
#     - ConfigMap (kubernetes_config_map)
#     - ExternalSecret CR (ESO sync)
#     - ArgoCD Application CR (separate Helm release per env)
#   IRSA trust policies cover both namespaces (StringEquals with list of values).
# =============================================================================

# ── Read secret values from Secrets Manager ───────────────────────────────────
# Resolved from the AWS API (not Kubernetes) — always available in a single apply.
# module.database creates and populates these secrets in the same apply run.

data "aws_secretsmanager_secret_version" "database" {
  secret_id = module.database.db_secret_arn

  depends_on = [module.database]
}

data "aws_secretsmanager_secret_version" "application" {
  secret_id = module.database.application_secret_arn

  depends_on = [module.database]
}

# ── Namespaces ────────────────────────────────────────────────────────────────
# All three namespaces created by Terraform — no manual kubectl required.
# Labels follow k8s well-known label conventions for namespace discovery.

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      name                           = "argocd"
      "app.kubernetes.io/managed-by" = "Terraform"
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_namespace" "cargotrack_dev" {
  metadata {
    name = "cargotrack-dev"
    labels = {
      name                           = "cargotrack-dev"
      environment                    = "dev"
      "app.kubernetes.io/managed-by" = "Terraform"
      "app.kubernetes.io/part-of"    = "cargotrack"
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_namespace" "cargotrack_prod" {
  metadata {
    name = "cargotrack-prod"
    labels = {
      name                           = "cargotrack-prod"
      environment                    = "prod"
      "app.kubernetes.io/managed-by" = "Terraform"
      "app.kubernetes.io/part-of"    = "cargotrack"
    }
  }

  depends_on = [module.eks]
}

# ── AWS Load Balancer Controller ──────────────────────────────────────────────
# Uses IRSA role cargotrack-irsa-alb-controller.
# ServiceAccount must match IRSA trust policy subject:
#   system:serviceaccount:kube-system:aws-load-balancer-controller

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.8.1" # pin — update deliberately
  namespace  = "kube-system"

  wait            = true
  timeout         = 300 # 5 minutes
  cleanup_on_fail = true

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  # AL2023 nodes block IMDS by default — pass VPC ID explicitly.
  set {
    name  = "vpcId"
    value = module.networking.vpc_id
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.irsa.alb_controller_role_arn
  }

  set {
    name  = "replicaCount"
    value = "2"
  }

  depends_on = [
    module.eks,
    module.irsa,
    kubernetes_namespace.cargotrack_dev,
    kubernetes_namespace.cargotrack_prod,
  ]
}

# ── Metrics Server ────────────────────────────────────────────────────────────
# Required for HPA. --kubelet-insecure-tls needed for EKS self-signed certs.
# --kubelet-preferred-address-types=InternalIP needed for private-subnet nodes.

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.1" # pin — update deliberately
  namespace  = "kube-system"

  wait            = true
  timeout         = 180
  cleanup_on_fail = true

  set {
    name  = "args[0]"
    value = "--kubelet-preferred-address-types=InternalIP"
  }

  set {
    name  = "args[1]"
    value = "--kubelet-insecure-tls"
  }

  depends_on = [
    module.eks,
    helm_release.aws_load_balancer_controller,
  ]
}

# ── Cluster Autoscaler ────────────────────────────────────────────────────────
# Uses IRSA role cargotrack-irsa-cluster-autoscaler.
# Node group in modules/eks has the required auto-discovery tags.

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.37.0" # pin — update deliberately
  namespace  = "kube-system"

  wait            = true
  timeout         = 180
  cleanup_on_fail = true

  set {
    name  = "autoDiscovery.clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  set {
    name  = "rbac.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.irsa.cluster_autoscaler_role_arn
  }

  set {
    name  = "extraArgs.expander"
    value = "least-waste"
  }

  set {
    name  = "extraArgs.balance-similar-node-groups"
    value = "true"
  }

  set {
    name  = "extraArgs.skip-nodes-with-system-pods"
    value = "false"
  }

  depends_on = [
    module.eks,
    module.irsa,
    helm_release.metrics_server,
  ]
}

# ── Bootstrap K8s Secrets ─────────────────────────────────────────────────────
# WHY BOOTSTRAP SECRETS EXIST:
#
#   ESO installs and syncs asynchronously. On the first apply, there is a window
#   between when the ESO Helm release completes (wait=true) and when the
#   ExternalSecret CR is first reconciled and the secret is populated.
#   Without a bootstrap secret, pods scheduled in that window crash with:
#     "secret cargotrack-secrets not found"
#
#   These Terraform-managed secrets provide immediate availability so pods
#   start successfully on the very first apply.
#
#   ESO ExternalSecret CRs (below) use creationPolicy=Merge to take over
#   ownership of these secrets after ESO reconciles (~10-30 seconds after apply).
#   From that point forward, ESO owns rotation — Terraform does not need to
#   re-run to update secret values in Kubernetes.
#
#   On destroy: ExternalSecret CRs are destroyed first (deletionPolicy=Retain
#   means ESO does NOT delete the K8s secret on CR deletion). Then Terraform
#   destroys the kubernetes_secret resource. This avoids any double-delete race.

resource "kubernetes_secret" "cargotrack_secrets_dev" {
  metadata {
    name      = "cargotrack-secrets"
    namespace = kubernetes_namespace.cargotrack_dev.metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "Terraform"
      "app.kubernetes.io/part-of"    = "cargotrack"
      environment                    = "dev"
    }
    annotations = {
      "cargotrack.io/secret-source"  = "aws-secrets-manager"
      "cargotrack.io/eso-managed"    = "true"
    }
  }

  type = "Opaque"

  data = {
    DATABASE_PASSWORD = jsondecode(data.aws_secretsmanager_secret_version.database.secret_string)["password"]
    JWT_SECRET        = jsondecode(data.aws_secretsmanager_secret_version.application.secret_string)["jwt_secret"]
    ADMIN_PASSWORD    = jsondecode(data.aws_secretsmanager_secret_version.application.secret_string)["admin_password"]
  }

  depends_on = [
    kubernetes_namespace.cargotrack_dev,
    data.aws_secretsmanager_secret_version.database,
    data.aws_secretsmanager_secret_version.application,
  ]
}

resource "kubernetes_secret" "cargotrack_secrets_prod" {
  metadata {
    name      = "cargotrack-secrets"
    namespace = kubernetes_namespace.cargotrack_prod.metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "Terraform"
      "app.kubernetes.io/part-of"    = "cargotrack"
      environment                    = "prod"
    }
    annotations = {
      "cargotrack.io/secret-source" = "aws-secrets-manager"
      "cargotrack.io/eso-managed"   = "true"
    }
  }

  type = "Opaque"

  data = {
    DATABASE_PASSWORD = jsondecode(data.aws_secretsmanager_secret_version.database.secret_string)["password"]
    JWT_SECRET        = jsondecode(data.aws_secretsmanager_secret_version.application.secret_string)["jwt_secret"]
    ADMIN_PASSWORD    = jsondecode(data.aws_secretsmanager_secret_version.application.secret_string)["admin_password"]
  }

  depends_on = [
    kubernetes_namespace.cargotrack_prod,
    data.aws_secretsmanager_secret_version.database,
    data.aws_secretsmanager_secret_version.application,
  ]
}

# ── Bootstrap ConfigMaps ──────────────────────────────────────────────────────
# WHY TERRAFORM (not Helm / ArgoCD) creates these ConfigMaps:
#
#   The Helm chart's configmap.yaml template would render AWS resource identifiers
#   (DATABASE_HOST, SQS_COMPLIANCE_QUEUE_URL, etc.) from values files in Git.
#   Those values are empty in Git (they are Terraform outputs, not static values).
#   ArgoCD deploys whatever is in Git at sync time → empty values → init container
#   fails with: "nc: bad address ''" for the database connectivity check.
#
#   SOLUTION: Terraform creates the ConfigMaps directly using its own module outputs.
#   This is the single-apply-safe pattern. ArgoCD does not own or manage these CMs.
#
#   Each environment gets its own ConfigMap pointing to the same shared AWS
#   infrastructure (same RDS endpoint, same S3 bucket, same SQS queue). In a full
#   multi-environment setup, each would have its own database. For this evaluation,
#   both environments share the infrastructure tier but remain namespace-isolated.

resource "kubernetes_config_map" "cargotrack_aws_config_dev" {
  metadata {
    name      = "cargotrack-aws-config"
    namespace = kubernetes_namespace.cargotrack_dev.metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "Terraform"
      "app.kubernetes.io/part-of"    = "cargotrack"
      environment                    = "dev"
    }
    annotations = {
      "cargotrack.io/ssm-path" = "/cargotrack/dev/"
    }
  }

  data = {
    AWS_DEFAULT_REGION       = var.aws_region
    DATABASE_HOST            = split(":", module.database.db_endpoint)[0]
    DATABASE_PORT            = "5432"
    DATABASE_NAME            = "cargotrack"
    DATABASE_USER            = "cargotrack"
    S3_BUCKET                = module.storage.bucket_id
    EVENT_BUS_NAME           = module.eventing.event_bus_name
    SQS_COMPLIANCE_QUEUE_URL = module.eventing.compliance_queue_url
    DYNAMO_AUDIT_TABLE       = module.audit.table_name
    DB_SECRET_ARN            = module.database.db_secret_arn
    APP_SECRET_ARN           = module.database.application_secret_arn
    # SSM path prefix — services can self-discover config via SSM SDK if needed
    SSM_CONFIG_PATH          = "/cargotrack/dev/"
  }

  depends_on = [
    kubernetes_namespace.cargotrack_dev,
    module.database,
    module.storage,
    module.eventing,
    module.audit,
  ]
}

resource "kubernetes_config_map" "cargotrack_aws_config_prod" {
  metadata {
    name      = "cargotrack-aws-config"
    namespace = kubernetes_namespace.cargotrack_prod.metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "Terraform"
      "app.kubernetes.io/part-of"    = "cargotrack"
      environment                    = "prod"
    }
    annotations = {
      "cargotrack.io/ssm-path" = "/cargotrack/dev/"
    }
  }

  data = {
    AWS_DEFAULT_REGION       = var.aws_region
    DATABASE_HOST            = split(":", module.database.db_endpoint)[0]
    DATABASE_PORT            = "5432"
    DATABASE_NAME            = "cargotrack"
    DATABASE_USER            = "cargotrack"
    S3_BUCKET                = module.storage.bucket_id
    EVENT_BUS_NAME           = module.eventing.event_bus_name
    SQS_COMPLIANCE_QUEUE_URL = module.eventing.compliance_queue_url
    DYNAMO_AUDIT_TABLE       = module.audit.table_name
    DB_SECRET_ARN            = module.database.db_secret_arn
    APP_SECRET_ARN           = module.database.application_secret_arn
    SSM_CONFIG_PATH          = "/cargotrack/dev/"
  }

  depends_on = [
    kubernetes_namespace.cargotrack_prod,
    module.database,
    module.storage,
    module.eventing,
    module.audit,
  ]
}

# ── ArgoCD ────────────────────────────────────────────────────────────────────
# Installed after LBC — ArgoCD server NLB is created by the LBC.
#
# The root Application CR is created by a SEPARATE kubernetes_manifest resource
# below. This gives Terraform explicit lifecycle control and avoids the
# server.additionalApplications Helm pattern (which has its own timeout problem
# when the Application CR has a finalizer and Helm tries to upgrade/uninstall).

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.4.4" # pin — update deliberately
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  wait            = true
  timeout         = 600 # 10 minutes — ArgoCD has many components
  cleanup_on_fail = true

  # Expose ArgoCD server via an internet-facing NLB
  set {
    name  = "server.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "server.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme"
    value = "internet-facing"
  }

  set {
    name  = "server.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "external"
  }

  # TLS terminated at NLB/CloudFront — run ArgoCD server in insecure mode
  set {
    name  = "server.extraArgs[0]"
    value = "--insecure"
  }

  depends_on = [
    module.eks,
    kubernetes_namespace.argocd,
    kubernetes_secret.cargotrack_secrets_dev,
    kubernetes_secret.cargotrack_secrets_prod,
    helm_release.aws_load_balancer_controller,
    helm_release.cluster_autoscaler,
    helm_release.metrics_server,
  ]
}

# ── External Secrets Operator ─────────────────────────────────────────────────
# ESO is installed cluster-wide via Helm. It installs the ExternalSecret CRDs
# before the kubernetes_manifest resources below attempt to apply them.
#
# wait=true ensures the ESO controller is running and CRDs are registered before
# Terraform attempts to apply ClusterSecretStore and ExternalSecret manifests.
#
# IRSA: The ESO controller ServiceAccount (external-secrets/external-secrets) is
# annotated with the ESO IRSA role ARN so it can authenticate to AWS without
# any static credentials in the cluster.
#
# The ESO IRSA role has least-privilege access:
#   - secretsmanager:GetSecretValue on cargotrack-* secrets only
#   - ssm:GetParameter on /cargotrack/* parameters only
#   - kms:Decrypt for the CargoTrack CMK

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "0.9.20" # pin — update deliberately
  namespace        = "external-secrets"
  create_namespace = true

  wait            = true
  timeout         = 300 # 5 minutes — ESO installs CRDs + controller
  cleanup_on_fail = true

  # Annotate the ESO controller ServiceAccount with the IRSA role ARN.
  # This is how ESO authenticates to AWS Secrets Manager and SSM Parameter Store
  # without any static AWS credentials in the cluster. Pure IRSA — zero credentials.
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.irsa.eso_role_arn
  }

  # Install CRDs — required for ClusterSecretStore and ExternalSecret manifests below
  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [
    module.eks,
    module.irsa,
    helm_release.argocd,
  ]
}

# ── ClusterSecretStore: AWS Secrets Manager ───────────────────────────────────
# Cluster-wide store serving both cargotrack-dev and cargotrack-prod namespaces.
# Uses jwt auth with the ESO controller ServiceAccount (IRSA-annotated) —
# no static AWS keys stored anywhere in the cluster.
#
# DESIGN: ClusterSecretStore (not SecretStore) avoids creating duplicate stores
# per namespace. One store, multiple ExternalSecret CRs across namespaces.

resource "kubernetes_manifest" "cluster_secret_store_sm" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "aws-secrets-manager"
      labels = {
        "app.kubernetes.io/managed-by" = "Terraform"
        "app.kubernetes.io/part-of"    = "cargotrack"
      }
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.aws_region
          auth = {
            jwt = {
              serviceAccountRef = {
                # Reference the ESO controller ServiceAccount that has the IRSA annotation.
                # ESO exchanges the OIDC token for short-lived AWS credentials via STS.
                name      = "external-secrets"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  }

  field_manager {
    force_conflicts = true
  }

  depends_on = [helm_release.external_secrets]
}

# ── ClusterSecretStore: AWS SSM Parameter Store ───────────────────────────────
# Separate cluster-wide store for SSM-sourced configuration.
# The same ESO ServiceAccount (IRSA role) covers both Secrets Manager and SSM.

resource "kubernetes_manifest" "cluster_secret_store_ssm" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "aws-ssm-parameter-store"
      labels = {
        "app.kubernetes.io/managed-by" = "Terraform"
        "app.kubernetes.io/part-of"    = "cargotrack"
      }
    }
    spec = {
      provider = {
        aws = {
          service = "ParameterStore"
          region  = var.aws_region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  }

  field_manager {
    force_conflicts = true
  }

  depends_on = [helm_release.external_secrets]
}

# ── ExternalSecret: cargotrack-dev namespace ──────────────────────────────────
# Syncs sensitive values from AWS Secrets Manager into the cargotrack-dev
# kubernetes_secret (bootstrap secret above).
#
# creationPolicy: Merge — ESO merges into the existing Terraform-created secret
#   rather than creating a new one. This is the one-apply-safe design choice.
#   If the secret doesn't exist yet, ESO creates it. If it exists, ESO merges.
#
# deletionPolicy: Retain — When this ExternalSecret CR is deleted (by Terraform
#   on destroy), ESO does NOT delete the kubernetes_secret. Terraform destroys
#   the kubernetes_secret separately. This prevents a double-delete race condition.
#
# refreshInterval: 1h — ESO polls Secrets Manager every hour to detect rotation.
#   When Secrets Manager auto-rotates a secret, the updated value propagates to
#   the Kubernetes secret within 1 hour — no Terraform apply required.

resource "kubernetes_manifest" "external_secret_dev" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "cargotrack-secrets-sync"
      namespace = "cargotrack-dev"
      labels = {
        "app.kubernetes.io/managed-by" = "Terraform"
        "app.kubernetes.io/part-of"    = "cargotrack"
        environment                    = "dev"
      }
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "aws-secrets-manager"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "cargotrack-secrets"
        creationPolicy = "Merge"
        deletionPolicy = "Retain"
      }
      data = [
        {
          secretKey = "DATABASE_PASSWORD"
          remoteRef = {
            key      = "cargotrack-database-secret-v2"
            property = "password"
          }
        },
        {
          secretKey = "JWT_SECRET"
          remoteRef = {
            key      = "cargotrack-application-secret-v2"
            property = "jwt_secret"
          }
        },
        {
          secretKey = "ADMIN_PASSWORD"
          remoteRef = {
            key      = "cargotrack-application-secret-v2"
            property = "admin_password"
          }
        },
      ]
    }
  }

  field_manager {
    force_conflicts = true
  }

  depends_on = [
    kubernetes_manifest.cluster_secret_store_sm,
    kubernetes_secret.cargotrack_secrets_dev,
    kubernetes_namespace.cargotrack_dev,
  ]
}

# ── ExternalSecret: cargotrack-prod namespace ─────────────────────────────────
# Identical pattern to the dev ExternalSecret — same Secrets Manager sources,
# different target namespace. Both environments share the same secrets for this
# single-cluster evaluation setup.

resource "kubernetes_manifest" "external_secret_prod" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "cargotrack-secrets-sync"
      namespace = "cargotrack-prod"
      labels = {
        "app.kubernetes.io/managed-by" = "Terraform"
        "app.kubernetes.io/part-of"    = "cargotrack"
        environment                    = "prod"
      }
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "aws-secrets-manager"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "cargotrack-secrets"
        creationPolicy = "Merge"
        deletionPolicy = "Retain"
      }
      data = [
        {
          secretKey = "DATABASE_PASSWORD"
          remoteRef = {
            key      = "cargotrack-database-secret-v2"
            property = "password"
          }
        },
        {
          secretKey = "JWT_SECRET"
          remoteRef = {
            key      = "cargotrack-application-secret-v2"
            property = "jwt_secret"
          }
        },
        {
          secretKey = "ADMIN_PASSWORD"
          remoteRef = {
            key      = "cargotrack-application-secret-v2"
            property = "admin_password"
          }
        },
      ]
    }
  }

  field_manager {
    force_conflicts = true
  }

  depends_on = [
    kubernetes_manifest.cluster_secret_store_sm,
    kubernetes_secret.cargotrack_secrets_prod,
    kubernetes_namespace.cargotrack_prod,
  ]
}

# ── Pre-destroy ingress cleanup ───────────────────────────────────────────────
# PURPOSE: Ensure ALBs are deprovisioned in BOTH namespaces before LBC uninstalls.
#
# WHY NEEDED:
#   Without cascade-delete finalizers on the ArgoCD Application CRs, deleting
#   the Application CRs does NOT garbage-collect Ingress resources. If Ingress
#   objects exist when LBC is uninstalled, the ALBs are orphaned in AWS.
#
#   Finalizers were intentionally removed to avoid Terraform timeout issues
#   (kubernetes_manifest has no configurable delete timeout).
#
# WHAT IT DOES ON DESTROY:
#   1. Configures kubectl using aws eks update-kubeconfig
#   2. Deletes all Ingress resources in cargotrack-dev AND cargotrack-prod
#   3. Waits 30s for LBC to deprovision both ALBs
#
# Run from GitHub Actions (ubuntu-latest) — bash is always available there.
# If running locally on Windows, use: 'terraform destroy' from WSL or Git Bash.

resource "null_resource" "pre_destroy_ingress_cleanup" {
  triggers = {
    cluster_name = module.eks.cluster_name
    aws_region   = var.aws_region
    ns_dev       = "cargotrack-dev"
    ns_prod      = "cargotrack-prod"
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -e
      echo "[pre-destroy] Configuring kubectl for ${self.triggers.cluster_name}..."
      aws eks update-kubeconfig \
        --name "${self.triggers.cluster_name}" \
        --region "${self.triggers.aws_region}" \
        --kubeconfig "/tmp/cargotrack-kube-destroy.conf" 2>/dev/null

      for NS in "${self.triggers.ns_dev}" "${self.triggers.ns_prod}"; do
        echo "[pre-destroy] Deleting Ingress resources in namespace: ${NS}..."
        KUBECONFIG="/tmp/cargotrack-kube-destroy.conf" \
          kubectl delete ingress --all \
            -n "${NS}" \
            --timeout=120s \
            --ignore-not-found=true 2>/dev/null || true
      done

      echo "[pre-destroy] Waiting 30s for ALB deprovisioning..."
      sleep 30
      echo "[pre-destroy] Ingress cleanup complete."
    EOT
  }

  # Destroy ordering:
  #   On destroy: argocd_root_app is destroyed FIRST (depends on null_resource),
  #   then null_resource cleanup runs (deletes Ingress in both namespaces),
  #   then helm_release.argocd is destroyed.
  #   kubectl delete ingress is idempotent — works whether or not ArgoCD app CRs exist.
  depends_on = [
    helm_release.argocd,
  ]
}

# ── ArgoCD Application: cargotrack-dev ────────────────────────────────────────
# Deploys the CargoTrack Helm chart to the cargotrack-dev namespace.
#
# IRSA role ARNs are injected as Helm parameters — these are Terraform outputs
# that cannot be committed to values-dev.yaml without a post-apply edit cycle.
# The parameters override the empty roleArn fields in values files at sync time.
#
# global.namespace = "cargotrack-dev" is injected as a Helm parameter so the
# Helm chart templates render all resources in the correct namespace without
# requiring changes to the values files in the cargotrack-helm repo.

resource "kubernetes_manifest" "cargotrack_dev_app" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "cargotrack-dev"
      namespace = "argocd"
      # finalizers intentionally omitted — see null_resource.pre_destroy_ingress_cleanup
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/CargoTrack-Org/cargotrack-helm.git"
        targetRevision = "main"
        path           = "cargotrack"
        helm = {
          valueFiles = [
            "values.yaml",
            "values-dev.yaml",
          ]
          parameters = [
            # Namespace injection — tells Helm chart which namespace to deploy into
            {
              name  = "global.namespace"
              value = "cargotrack-dev"
            },
            {
              name  = "global.environment"
              value = "dev"
            },
            # IRSA role ARNs — injected by Terraform from module outputs
            {
              name  = "coreService.serviceAccount.roleArn"
              value = module.irsa.core_service_role_arn
            },
            {
              name  = "documentService.serviceAccount.roleArn"
              value = module.irsa.document_service_role_arn
            },
            {
              name  = "aiService.serviceAccount.roleArn"
              value = module.irsa.ai_service_role_arn
            },
            # AI configuration — real Bedrock in dev
            {
              name  = "aiService.env.MOCK_AGENT"
              value = "false"
            },
            {
              name  = "aiService.env.TEXTRACT_ENABLED"
              value = "true"
            },
            {
              name  = "aiService.env.LLM_PROVIDER"
              value = "bedrock"
            },
          ]
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "cargotrack-dev"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=false", # Namespace already created by Terraform above
          "ServerSideApply=true",
        ]
        retry = {
          limit = 3
          backoff = {
            duration    = "5s"
            maxDuration = "3m"
            factor      = 2
          }
        }
      }
    }
  }

  field_manager {
    force_conflicts = true
  }

  depends_on = [
    helm_release.argocd,
    kubernetes_namespace.cargotrack_dev,
    kubernetes_config_map.cargotrack_aws_config_dev,
    kubernetes_secret.cargotrack_secrets_dev,
    kubernetes_manifest.external_secret_dev,
    module.irsa,
  ]
}

# ── ArgoCD Application: cargotrack-prod ───────────────────────────────────────
# Deploys the CargoTrack Helm chart to the cargotrack-prod namespace.
# Uses values-prod.yaml overrides (higher replica counts, prod-grade settings).
# Bedrock and Textract are enabled for prod — real AI compliance checks.

resource "kubernetes_manifest" "cargotrack_prod_app" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "cargotrack-prod"
      namespace = "argocd"
      # finalizers intentionally omitted — see null_resource.pre_destroy_ingress_cleanup
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/CargoTrack-Org/cargotrack-helm.git"
        targetRevision = "main"
        path           = "cargotrack"
        helm = {
          valueFiles = [
            "values.yaml",
            "values-prod.yaml",
          ]
          parameters = [
            # Namespace injection
            {
              name  = "global.namespace"
              value = "cargotrack-prod"
            },
            {
              name  = "global.environment"
              value = "prod"
            },
            # IRSA role ARNs — same roles as dev (trust policy covers both namespaces)
            {
              name  = "coreService.serviceAccount.roleArn"
              value = module.irsa.core_service_role_arn
            },
            {
              name  = "documentService.serviceAccount.roleArn"
              value = module.irsa.document_service_role_arn
            },
            {
              name  = "aiService.serviceAccount.roleArn"
              value = module.irsa.ai_service_role_arn
            },
            # AI configuration — full Bedrock + Textract in prod
            {
              name  = "aiService.env.MOCK_AGENT"
              value = "false"
            },
            {
              name  = "aiService.env.TEXTRACT_ENABLED"
              value = "true"
            },
            {
              name  = "aiService.env.LLM_PROVIDER"
              value = "bedrock"
            },
          ]
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "cargotrack-prod"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=false",
          "ServerSideApply=true",
        ]
        retry = {
          limit = 3
          backoff = {
            duration    = "5s"
            maxDuration = "3m"
            factor      = 2
          }
        }
      }
    }
  }

  field_manager {
    force_conflicts = true
  }

  depends_on = [
    helm_release.argocd,
    kubernetes_namespace.cargotrack_prod,
    kubernetes_config_map.cargotrack_aws_config_prod,
    kubernetes_secret.cargotrack_secrets_prod,
    kubernetes_manifest.external_secret_prod,
    module.irsa,
  ]
}

# ── ArgoCD App-of-Apps Bootstrap ─────────────────────────────────────────────
# Creates the root Application CR (app-of-apps pattern) that watches
# cargotrack-gitops/apps/ for Application manifests.
#
# DESIGN DECISIONS:
#   1. kubernetes_manifest (not server.additionalApplications):
#      Gives Terraform explicit lifecycle control.
#   2. NO cascade-delete finalizer:
#      Avoids kubernetes_manifest deletion timeout (no configurable timeout).
#      ALB cleanup handled by null_resource.pre_destroy_ingress_cleanup.
#   3. No CRD bootstrap issue:
#      depends_on = [helm_release.argocd] ensures CRDs exist before this applies.
#   4. Destroy sequence guarantee:
#      argocd_root_app (no direct destruction dependency on null_resource, but
#      cargotrack_dev/prod_app depend on null_resource ensuring correct ALB cleanup):
#      root-app destroyed → dev/prod-app destroyed → null_resource cleanup runs
#      → ESO CRs → ESO Helm → ArgoCD Helm → namespaces → EKS ✅

resource "kubernetes_manifest" "argocd_root_app" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root-app"
      namespace = "argocd"
      # finalizers intentionally omitted:
      #   Setting finalizers = [] causes a provider inconsistency error because
      #   the K8s API returns null for empty finalizers, not [].
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/CargoTrack-Org/cargotrack-gitops.git"
        targetRevision = "main"
        path           = "apps"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true",
        ]
      }
    }
  }

  field_manager {
    force_conflicts = true
  }

  depends_on = [
    helm_release.argocd,
    kubernetes_namespace.argocd,
    kubernetes_manifest.cargotrack_dev_app,
    kubernetes_manifest.cargotrack_prod_app,
    # Destroy ordering: argocd_root_app depends on null_resource so on destroy:
    # root-app is destroyed FIRST, THEN null_resource ingress cleanup runs,
    # THEN ArgoCD Helm can be uninstalled cleanly (no orphaned ALBs).
    null_resource.pre_destroy_ingress_cleanup,
  ]
}
