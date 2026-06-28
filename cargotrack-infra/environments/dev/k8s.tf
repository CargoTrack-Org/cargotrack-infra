data "aws_secretsmanager_secret_version" "database" {
  secret_id = module.database.db_secret_arn

  depends_on = [module.database]
}

data "aws_secretsmanager_secret_version" "application" {
  secret_id = module.database.application_secret_arn

  depends_on = [module.database]
}

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

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.8.1"
  namespace  = "kube-system"

  wait            = true
  timeout         = 300
  cleanup_on_fail = true

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

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

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.1"
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

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.37.0"
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

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.4.4"
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  wait            = true
  timeout         = 600
  cleanup_on_fail = true

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

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "0.9.20"
  namespace        = "external-secrets"
  create_namespace = true

  wait            = true
  timeout         = 300
  cleanup_on_fail = true

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.irsa.eso_role_arn
  }

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

resource "kubectl_manifest" "cluster_secret_store_sm" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ClusterSecretStore
    metadata:
      name: aws-secrets-manager
      labels:
        app.kubernetes.io/managed-by: Terraform
        app.kubernetes.io/part-of: cargotrack
    spec:
      provider:
        aws:
          service: SecretsManager
          region: ${var.aws_region}
          auth:
            jwt:
              serviceAccountRef:
                name: external-secrets
                namespace: external-secrets
  YAML

  force_conflicts   = true
  server_side_apply = true

  depends_on = [helm_release.external_secrets]
}

resource "kubectl_manifest" "cluster_secret_store_ssm" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ClusterSecretStore
    metadata:
      name: aws-ssm-parameter-store
      labels:
        app.kubernetes.io/managed-by: Terraform
        app.kubernetes.io/part-of: cargotrack
    spec:
      provider:
        aws:
          service: ParameterStore
          region: ${var.aws_region}
          auth:
            jwt:
              serviceAccountRef:
                name: external-secrets
                namespace: external-secrets
  YAML

  force_conflicts   = true
  server_side_apply = true

  depends_on = [helm_release.external_secrets]
}

resource "kubectl_manifest" "external_secret_dev" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: cargotrack-secrets-sync
      namespace: cargotrack-dev
      labels:
        app.kubernetes.io/managed-by: Terraform
        app.kubernetes.io/part-of: cargotrack
        environment: dev
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: aws-secrets-manager
        kind: ClusterSecretStore
      target:
        name: cargotrack-secrets
        creationPolicy: Merge
        deletionPolicy: Retain
      data:
        - secretKey: DATABASE_PASSWORD
          remoteRef:
            key: cargotrack-database-secret-v2
            property: password
        - secretKey: JWT_SECRET
          remoteRef:
            key: cargotrack-application-secret-v2
            property: jwt_secret
        - secretKey: ADMIN_PASSWORD
          remoteRef:
            key: cargotrack-application-secret-v2
            property: admin_password
  YAML

  force_conflicts   = true
  server_side_apply = true

  depends_on = [
    kubectl_manifest.cluster_secret_store_sm,
    kubernetes_secret.cargotrack_secrets_dev,
    kubernetes_namespace.cargotrack_dev,
  ]
}

resource "kubectl_manifest" "external_secret_prod" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: cargotrack-secrets-sync
      namespace: cargotrack-prod
      labels:
        app.kubernetes.io/managed-by: Terraform
        app.kubernetes.io/part-of: cargotrack
        environment: prod
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: aws-secrets-manager
        kind: ClusterSecretStore
      target:
        name: cargotrack-secrets
        creationPolicy: Merge
        deletionPolicy: Retain
      data:
        - secretKey: DATABASE_PASSWORD
          remoteRef:
            key: cargotrack-database-secret-v2
            property: password
        - secretKey: JWT_SECRET
          remoteRef:
            key: cargotrack-application-secret-v2
            property: jwt_secret
        - secretKey: ADMIN_PASSWORD
          remoteRef:
            key: cargotrack-application-secret-v2
            property: admin_password
  YAML

  force_conflicts   = true
  server_side_apply = true

  depends_on = [
    kubectl_manifest.cluster_secret_store_sm,
    kubernetes_secret.cargotrack_secrets_prod,
    kubernetes_namespace.cargotrack_prod,
  ]
}

resource "null_resource" "pre_destroy_ingress_cleanup" {
  triggers = {
    cluster_name = module.eks.cluster_name
    aws_region   = var.aws_region
    ns_dev       = "cargotrack-dev"
    ns_prod      = "cargotrack-prod"
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["powershell", "-Command"]
    command     = <<-EOT
      Write-Host "[pre-destroy] Configuring kubectl for ${self.triggers.cluster_name}..."
      aws eks update-kubeconfig --name "${self.triggers.cluster_name}" --region "${self.triggers.aws_region}" --kubeconfig "$env:TEMP\cargotrack-kube-destroy.conf" 2>$null
      $env:KUBECONFIG = "$env:TEMP\cargotrack-kube-destroy.conf"

      Write-Host "[pre-destroy] Deleting Ingress resources in ${self.triggers.ns_dev}..."
      kubectl delete ingress --all -n "${self.triggers.ns_dev}" --timeout=120s --ignore-not-found=true 2>$null

      Write-Host "[pre-destroy] Deleting Ingress resources in ${self.triggers.ns_prod}..."
      kubectl delete ingress --all -n "${self.triggers.ns_prod}" --timeout=120s --ignore-not-found=true 2>$null

      Write-Host "[pre-destroy] Waiting 90s for AWS to release ALB Elastic IPs..."
      Start-Sleep -Seconds 90
      Write-Host "[pre-destroy] Ingress cleanup complete."
    EOT
  }

  depends_on = [
    helm_release.argocd,
  ]
}

resource "kubectl_manifest" "argocd_root_app" {
  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: root-app
      namespace: argocd
    spec:
      project: default
      source:
        repoURL: https://github.com/CargoTrack-Org/cargotrack-gitops.git
        targetRevision: main
        path: apps
      destination:
        server: https://kubernetes.default.svc
        namespace: argocd
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
  YAML

  force_conflicts   = true
  server_side_apply = true

  depends_on = [
    helm_release.argocd,
    kubernetes_namespace.argocd,
    kubernetes_config_map.cargotrack_aws_config_dev,
    kubernetes_config_map.cargotrack_aws_config_prod,
    kubernetes_secret.cargotrack_secrets_dev,
    kubernetes_secret.cargotrack_secrets_prod,
    kubectl_manifest.external_secret_dev,
    kubectl_manifest.external_secret_prod,
    null_resource.pre_destroy_ingress_cleanup,
  ]
}
