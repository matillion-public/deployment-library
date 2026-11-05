# modules/aws/eks/main.tf

resource "aws_iam_role" "eks_role" {
  name = lookup(var.resource_names, "eks_role", join("-", [var.name, "eks-role", var.random_string_salt]))

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "eks_policy_attachment" {
  role       = aws_iam_role.eks_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "eks_cluster" {
  name     = lookup(var.resource_names, "eks_cluster", join("-", [var.name, "eks-cluster", var.random_string_salt]))
  role_arn = aws_iam_role.eks_role.arn


  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
    security_group_ids      = var.security_group_ids
  }

  access_config {
    authentication_mode = var.authentication_mode

    # The provider treats an unset value as false on create, which leaves the creating
    # principal without an access entry. It records true in state for clusters that
    # predate access_config, so leaving it unset plans a replacement of those clusters.
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = var.tags
}

resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.additional_admin_principal_arns)

  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = each.value
  type          = "STANDARD"

  tags = var.tags

  lifecycle {
    precondition {
      condition     = var.authentication_mode != "CONFIG_MAP"
      error_message = "additional_admin_principal_arns requires authentication_mode API_AND_CONFIG_MAP or API; access entries do not exist in CONFIG_MAP mode."
    }
  }
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = aws_eks_access_entry.admin

  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = each.value.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

resource "aws_eks_addon" "vpc-cni" {
  cluster_name = aws_eks_cluster.eks_cluster.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "kube-proxy" {
  cluster_name = aws_eks_cluster.eks_cluster.name
  addon_name   = "kube-proxy"
}
resource "aws_iam_role" "fargate_pod_execution_role" {
  name = lookup(var.resource_names, "fargate_pod_execution_role", join("-", [var.name, "fargate-pod-execution-role", var.random_string_salt]))

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks-fargate-pods.amazonaws.com"
        }
      },
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution_policy" {
  role       = aws_iam_role.fargate_pod_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

resource "aws_iam_policy" "dpc_policy" {
  name        = lookup(var.resource_names, "dpc_policy", join("-", ["DataProductivityCloudAccess", var.random_string_salt]))
  description = "Policy for Maia with S3, Secrets Manager, Redshift, and IAM permissions"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetBucketLocation",
          "s3:ListAllMyBuckets"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecret",
          "secretsmanager:DeleteSecret",
          "secretsmanager:CreateSecret",
          "secretsmanager:ListSecrets"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "redshift:CreateUser",
          "redshift:AlterUser",
          "redshift:CreateDatabase",
          "redshift:AlterDatabase",
          "redshift:CreateSchema",
          "redshift:ModifyClusterIamRoles"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "iam:CreateRole",
          "iam:AttachRolePolicy",
          "iam:PassRole"
        ],
        "Resource" : "*"
      }
    ]
  })
}

# Create OIDC provider for the cluster to enable IRSA
data "tls_certificate" "eks" {
  url = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
  tags            = var.tags
}

locals {
  oidc_provider_path = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")

  service_account_subjects = [
    "system:serviceaccount:${var.namespace}:${var.service_account_name}",
    "system:serviceaccount:${var.namespace}:${var.script_runner_service_account_name}",
  ]
}

# Create IAM role for service accounts with S3 and Secrets Manager access
resource "aws_iam_role" "service_account_role" {
  name = lookup(var.resource_names, "service_account_role", join("-", [var.name, "service-account-role", var.random_string_salt]))
  tags = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = ["sts:AssumeRoleWithWebIdentity"]
      Condition = {
        # StringEquals with exact subjects. A StringLike pattern such as
        # `system:serviceaccount:*:...` lets a service account of that name in any
        # namespace assume this role.
        StringEquals = {
          "${local.oidc_provider_path}:aud" = "sts.amazonaws.com"
          "${local.oidc_provider_path}:sub" = local.service_account_subjects
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "service_account_dpc_policy" {
  role       = aws_iam_role.service_account_role.name
  policy_arn = aws_iam_policy.dpc_policy.arn
}

resource "aws_eks_fargate_profile" "fargate_profile" {
  cluster_name           = aws_eks_cluster.eks_cluster.name
  fargate_profile_name   = lookup(var.resource_names, "fargate_profile", join("-", [var.name, "fargate-profile", var.random_string_salt]))
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution_role.arn
  subnet_ids             = length(var.fargate_subnet_ids) > 0 ? var.fargate_subnet_ids : var.subnet_ids

  selector {
    namespace = var.namespace
  }

  selector {
    namespace = "kube-system"
  }

  selector {
    namespace = "prometheus"
  }

  tags = var.tags
}

# CoreDNS runs on Fargate nodes, which carry the eks.amazonaws.com/compute-type=fargate
# taint that CoreDNS does not tolerate by default. The toleration is supplied through the
# addon configuration, so it is applied through the AWS API and needs no access to the
# cluster endpoint. The addon waits for CoreDNS to become healthy, so the Fargate profile
# must exist first.
resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.eks_cluster.name
  addon_name   = "coredns"

  # Clusters created by earlier versions of this module have a self-managed CoreDNS
  # deployment that was patched with kubectl. OVERWRITE lets the addon adopt it; the
  # configuration below reproduces that patch.
  resolve_conflicts_on_create = "OVERWRITE"

  configuration_values = jsonencode({
    tolerations = [{
      key      = "eks.amazonaws.com/compute-type"
      operator = "Equal"
      value    = "fargate"
      effect   = "NoSchedule"
    }]
  })

  depends_on = [aws_eks_fargate_profile.fargate_profile]
}

resource "aws_s3_bucket" "log_bucket" {
  bucket = lookup(var.resource_names, "log_bucket", lower(join("-", [var.name, "log-bucket", var.random_string_salt])))


  tags = var.tags
}

resource "aws_s3_bucket_public_access_block" "log_bucket_block" {
  bucket = aws_s3_bucket.log_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

}

resource "aws_kms_key" "key" {
  description = "KMS key for EKS"
  tags        = var.tags
}

resource "aws_secretsmanager_secret" "eks_secret" {
  name       = lookup(var.resource_names, "eks_secret", join("-", [var.name, "eks-secret", var.random_string_salt]))
  kms_key_id = aws_kms_key.key.id

  tags = var.tags
}
