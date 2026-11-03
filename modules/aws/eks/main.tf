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

# Patch CoreDNS to run on Fargate nodes
# EKS Fargate nodes have the eks.amazonaws.com/compute-type=fargate taint
# which CoreDNS doesn't tolerate by default
#
# The patch talks to the cluster through a throwaway kubeconfig rather than the
# operator's own. Without --kubeconfig, update-kubeconfig writes into
# ~/.kube/config and switches its current context to this cluster, so whatever
# the operator runs next lands here instead of where they were working
# (DPC-58374). The auth_config_command output is there for adding the cluster
# deliberately.
resource "terraform_data" "coredns_fargate_patch" {
  depends_on = [aws_eks_fargate_profile.fargate_profile]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      KUBECONFIG="$(mktemp)"
      export KUBECONFIG
      trap 'rm -f "$KUBECONFIG"' EXIT
      aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.eks_cluster.name} --kubeconfig "$KUBECONFIG"
      kubectl patch deployment coredns -n kube-system --type json \
        -p='[{"op": "add", "path": "/spec/template/spec/tolerations/-", "value": {"key": "eks.amazonaws.com/compute-type", "operator": "Equal", "value": "fargate", "effect": "NoSchedule"}}]'
    EOT
  }
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
