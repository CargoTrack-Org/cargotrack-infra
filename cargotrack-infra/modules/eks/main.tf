data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }

  node_groups = {
    general = {
      name           = "${var.project_name}-general"
      instance_types = var.node_instance_types
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size
      capacity_type  = "ON_DEMAND"
      disk_size      = 50
    }
  }
}

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.project_name}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json
  tags               = local.common_tags
}

locals {
  cluster_policies = toset([
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController",
  ])
}

resource "aws_iam_role_policy_attachment" "cluster" {
  for_each   = local.cluster_policies
  role       = aws_iam_role.cluster.name
  policy_arn = each.value
}

resource "aws_eks_cluster" "main" {
  name     = var.project_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.app_subnet_ids
    security_group_ids      = [var.node_sg_id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-eks"
  })

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
  ]

  lifecycle {
    precondition {
      condition     = tonumber(var.cluster_version) >= 1.29
      error_message = "EKS cluster version must be 1.29 or higher."
    }
  }
}

data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-oidc-provider"
  })
}

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.project_name}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json
  tags               = local.common_tags
}

locals {
  node_policies = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
  ])
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each   = local.node_policies
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "amazon-cloudwatch-observability"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-cloudwatch-observability"
  })

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_node_group.this,
  ]
}

resource "aws_eks_node_group" "this" {
  for_each = local.node_groups

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = each.value.name
  node_role_arn   = aws_iam_role.node.arn

  subnet_ids = var.app_subnet_ids

  instance_types = each.value.instance_types
  capacity_type  = each.value.capacity_type
  disk_size      = each.value.disk_size

  scaling_config {
    min_size     = each.value.min_size
    max_size     = each.value.max_size
    desired_size = each.value.desired_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = merge(local.common_tags, {
    Name                                            = each.value.name
    "k8s.io/cluster-autoscaler/enabled"             = "true"
    "k8s.io/cluster-autoscaler/${var.project_name}" = "owned"
  })

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_cluster.main,
  ]
}
