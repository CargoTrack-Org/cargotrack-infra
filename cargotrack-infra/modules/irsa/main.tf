data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }

  oidc_host = replace(var.oidc_issuer_url, "https://", "")

  namespaces = ["cargotrack-dev", "cargotrack-prod"]

  services = {
    core_service     = "core-service"
    document_service = "document-service"
    ai_service       = "ai-service"
    alb_controller   = "aws-load-balancer-controller"
  }
}

data "aws_iam_policy_document" "core_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values = [
        "system:serviceaccount:cargotrack-dev:${local.services.core_service}",
        "system:serviceaccount:cargotrack-prod:${local.services.core_service}",
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "document_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values = [
        "system:serviceaccount:cargotrack-dev:${local.services.document_service}",
        "system:serviceaccount:cargotrack-prod:${local.services.document_service}",
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ai_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values = [
        "system:serviceaccount:cargotrack-dev:${local.services.ai_service}",
        "system:serviceaccount:cargotrack-prod:${local.services.ai_service}",
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "alb_controller_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:kube-system:${local.services.alb_controller}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "core_service" {
  name               = "${var.project_name}-irsa-core-service"
  assume_role_policy = data.aws_iam_policy_document.core_assume.json
  tags               = merge(local.common_tags, { Service = "core-service" })
}

resource "aws_iam_role" "document_service" {
  name               = "${var.project_name}-irsa-document-service"
  assume_role_policy = data.aws_iam_policy_document.document_assume.json
  tags               = merge(local.common_tags, { Service = "document-service" })
}

resource "aws_iam_role" "ai_service" {
  name               = "${var.project_name}-irsa-ai-service"
  assume_role_policy = data.aws_iam_policy_document.ai_assume.json
  tags               = merge(local.common_tags, { Service = "ai-service" })
}

resource "aws_iam_role" "alb_controller" {
  name               = "${var.project_name}-irsa-alb-controller"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume.json
  tags               = merge(local.common_tags, { Service = "aws-load-balancer-controller" })
}

data "aws_iam_policy_document" "core_service" {
  statement {
    sid     = "S3Documents"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = [
      var.documents_bucket_arn,
      "${var.documents_bucket_arn}/*",
    ]
  }

  statement {
    sid       = "EventBridgePublish"
    actions   = ["events:PutEvents"]
    resources = [var.event_bus_arn]
  }

  statement {
    sid       = "SQSCompliancePublish"
    actions   = ["sqs:SendMessage", "sqs:GetQueueAttributes"]
    resources = [var.compliance_queue_arn]
  }

  statement {
    sid       = "SecretsRead"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_secret_arn, var.app_secret_arn]
  }

  statement {
    sid       = "KMSDecrypt"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "core_service" {
  name   = "${var.project_name}-core-service-policy"
  role   = aws_iam_role.core_service.id
  policy = data.aws_iam_policy_document.core_service.json
}

data "aws_iam_policy_document" "document_service" {
  statement {
    sid     = "S3FullDocuments"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = [
      var.documents_bucket_arn,
      "${var.documents_bucket_arn}/*",
    ]
  }

  statement {
    sid = "TextractAccess"
    actions = [
      "textract:AnalyzeDocument",
      "textract:StartDocumentAnalysis",
      "textract:GetDocumentAnalysis",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "KMSDecrypt"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "document_service" {
  name   = "${var.project_name}-document-service-policy"
  role   = aws_iam_role.document_service.id
  policy = data.aws_iam_policy_document.document_service.json
}

data "aws_iam_policy_document" "ai_service" {
  statement {
    sid = "SQSComplianceConsume"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [var.compliance_queue_arn]
  }

  statement {
    sid     = "BedrockInvoke"
    actions = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = [
      "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.nova-pro-v1:0",
      "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.nova-lite-v1:0",
    ]
  }

  statement {
    sid = "TextractAccess"
    actions = [
      "textract:AnalyzeDocument",
      "textract:StartDocumentAnalysis",
      "textract:GetDocumentAnalysis",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "S3ReadDocuments"
    actions   = ["s3:GetObject"]
    resources = ["${var.documents_bucket_arn}/*"]
  }

  statement {
    sid       = "DynamoDBAuditWrite"
    actions   = ["dynamodb:PutItem", "dynamodb:GetItem"]
    resources = [var.audit_table_arn]
  }

  statement {
    sid       = "KMSDecrypt"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "ai_service" {
  name   = "${var.project_name}-ai-service-policy"
  role   = aws_iam_role.ai_service.id
  policy = data.aws_iam_policy_document.ai_service.json
}

data "aws_iam_policy_document" "alb_controller" {
  statement {
    sid = "AllowLoadBalancerManagement"
    actions = [
      "iam:CreateServiceLinkedRole",
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSecurityGroupRules",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "ec2:GetCoipPoolUsage",
      "ec2:DescribeCoipPools",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTags",
    ]
    resources = ["*"]
  }

  statement {
    sid = "AllowCertificateManager"
    actions = [
      "cognito-idp:DescribeUserPoolClient",
      "acm:ListCertificates",
      "acm:DescribeCertificate",
      "iam:ListServerCertificates",
      "iam:GetServerCertificate",
      "waf-regional:GetWebACL",
      "waf-regional:GetWebACLForResource",
      "waf-regional:AssociateWebACL",
      "waf-regional:DisassociateWebACL",
      "wafv2:GetWebACL",
      "wafv2:GetWebACLForResource",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "shield:GetSubscriptionState",
      "shield:DescribeProtection",
      "shield:CreateProtection",
      "shield:DeleteProtection",
    ]
    resources = ["*"]
  }

  statement {
    sid = "AllowSGManagement"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:CreateSecurityGroup",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["*"]
  }

  statement {
    sid = "AllowLBCreation"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:SetWebAcl",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:RemoveListenerCertificates",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowTaggingForALBController"
    actions   = ["ec2:DeleteSecurityGroup"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/elbv2.k8s.aws/cluster"
      values   = [var.cluster_name]
    }
  }
}

resource "aws_iam_role_policy" "alb_controller" {
  name   = "${var.project_name}-alb-controller-policy"
  role   = aws_iam_role.alb_controller.id
  policy = data.aws_iam_policy_document.alb_controller.json
}

data "aws_iam_policy_document" "cluster_autoscaler_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:kube-system:cluster-autoscaler"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster_autoscaler" {
  name               = "${var.project_name}-irsa-cluster-autoscaler"
  assume_role_policy = data.aws_iam_policy_document.cluster_autoscaler_assume.json
  tags               = merge(local.common_tags, { Service = "cluster-autoscaler" })
}

data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    sid = "AutoscalerDescribe"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeImages",
      "ec2:GetInstanceTypesFromInstanceRequirements",
      "eks:DescribeNodegroup",
    ]
    resources = ["*"]
  }

  statement {
    sid = "AutoscalerModify"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/${var.cluster_name}"
      values   = ["owned"]
    }
  }
}

resource "aws_iam_role_policy" "cluster_autoscaler" {
  name   = "${var.project_name}-cluster-autoscaler-policy"
  role   = aws_iam_role.cluster_autoscaler.id
  policy = data.aws_iam_policy_document.cluster_autoscaler.json
}

data "aws_iam_policy_document" "eso_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name               = "${var.project_name}-irsa-eso"
  assume_role_policy = data.aws_iam_policy_document.eso_assume.json
  tags               = merge(local.common_tags, { Service = "external-secrets-operator" })
}

data "aws_iam_policy_document" "eso" {
  statement {
    sid     = "SecretsManagerRead"
    actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:cargotrack-*",
    ]
  }

  statement {
    sid = "SSMParameterRead"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/cargotrack/*",
    ]
  }

  statement {
    sid       = "KMSDecrypt"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "eso" {
  name   = "${var.project_name}-eso-policy"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso.json
}
