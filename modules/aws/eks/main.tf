# modules/aws/eks/main.tf

provider "aws" {
  region = var.region
}

resource "aws_iam_role" "eks_role" {
  name = join("-", [var.name, "eks-role", var.random_string_salt])

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
  name     = join("-", [var.name, "eks-cluster", var.random_string_salt])
  role_arn = aws_iam_role.eks_role.arn
  

  vpc_config {
    subnet_ids = var.subnet_ids
  }

  tags = var.tags
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
  name = join("-", [var.name, "fargate-pod-execution-role", var.random_string_salt])

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
  name        = join("-", ["DataProductivityCloudAccess", var.random_string_salt])
  description = "Policy for Data Productivity Cloud with S3, Secrets Manager, Redshift, and IAM permissions"

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetBucketLocation",
          "s3:ListAllMyBuckets"
        ],
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Action": [
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecret",
          "secretsmanager:DeleteSecret",
          "secretsmanager:CreateSecret",
          "secretsmanager:ListSecrets"
        ],
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Action": [
          "redshift:CreateUser",
          "redshift:AlterUser",
          "redshift:CreateDatabase",
          "redshift:AlterDatabase",
          "redshift:CreateSchema",
          "redshift:ModifyClusterIamRoles"
        ],
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Action": [
          "iam:CreateRole",
          "iam:AttachRolePolicy",
          "iam:PassRole"
        ],
        "Resource": "*"
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

# Create IAM role for service accounts with S3 and Secrets Manager access
data "aws_iam_policy_document" "service_account_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringLike"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = [
        "system:serviceaccount:matillion:matillion-agent-sa",
        "system:serviceaccount:*:matillion-agent-sa"
      ] # Allow the service account in any namespace
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "service_account_role" {
  name               = join("-", [var.name, "service-account-role", var.random_string_salt])
  assume_role_policy = data.aws_iam_policy_document.service_account_assume_role_policy.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "service_account_dpc_policy" {
  role       = aws_iam_role.service_account_role.name
  policy_arn = aws_iam_policy.dpc_policy.arn
}

resource "aws_eks_fargate_profile" "fargate_profile" {
  cluster_name           = aws_eks_cluster.eks_cluster.name
  fargate_profile_name   = join("-", [var.name, "fargate-profile", var.random_string_salt])
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution_role.arn
  subnet_ids             = length(var.fargate_subnet_ids) > 0 ? var.fargate_subnet_ids : var.subnet_ids

  selector {
    namespace = "matillion"
  }

  selector {
    namespace = "kube-system"
  }

  tags = var.tags
}

resource "aws_s3_bucket" "log_bucket" {
  bucket = lower(join("-", [var.name, "log-bucket", var.random_string_salt]))
 

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
  name = join("-", [var.name, "eks-secret", var.random_string_salt])
  kms_key_id = aws_kms_key.key.id

  tags = var.tags
}
