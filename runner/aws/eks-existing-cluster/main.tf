# A Matillion runner in an EKS cluster that already exists, beside any other runners
# in it. Nothing here changes the cluster: each runner gets IAM roles trusted only by
# its own namespace's service accounts, and can use only secrets whose names start
# with its own prefix. Installing the runner chart with the outputs creates the
# namespace and service accounts; runner/helm/README.md "Shared Multi-Tenant
# Platform" shows how, and how to add the namespace to the cluster's Prometheus.

data "aws_partition" "current" {}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

# IRSA needs the cluster's OIDC provider. Looking it up fails the plan with the
# provider's URL when it doesn't exist, rather than leaving pods without credentials.
data "aws_iam_openid_connect_provider" "cluster" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

locals {
  namespace                          = var.name
  service_account_name               = "${var.name}-sa"
  script_runner_service_account_name = "${var.name}-script-runner-sa"
  secret_name_prefix                 = "matillion/${var.name}/"
}

module "identity" {
  source = "../../../modules/aws/runner-identity"

  name                 = var.name
  partition            = data.aws_partition.current.partition
  oidc_issuer_url      = data.aws_iam_openid_connect_provider.cluster.url
  namespace            = local.namespace
  service_account_name = local.service_account_name
  secret_name_prefix   = local.secret_name_prefix
  s3_bucket_arns       = var.s3_bucket_arns
  tags                 = var.tags
}

# The script runner runs code people write, so it gets a role of its own: the same
# buckets, and no secrets. With the runner's role, a script could read and overwrite
# every secret the runner keeps, OAuth tokens included.
module "script_runner_identity" {
  source = "../../../modules/aws/runner-identity"

  name                 = "${var.name}-scripts"
  partition            = data.aws_partition.current.partition
  oidc_issuer_url      = data.aws_iam_openid_connect_provider.cluster.url
  namespace            = local.namespace
  service_account_name = local.script_runner_service_account_name
  s3_bucket_arns       = var.s3_bucket_arns
  tags                 = var.tags
}

resource "aws_iam_role" "fargate_pod_execution" {
  count = length(var.fargate_subnet_ids) > 0 ? 1 : 0

  name = "${var.name}-fargate-pods"
  tags = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks-fargate-pods.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution" {
  count = length(var.fargate_subnet_ids) > 0 ? 1 : 0

  role       = aws_iam_role.fargate_pod_execution[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

# Fargate only runs pods in namespaces a profile selects, so the runner's own namespace
# needs one or its pods never schedule.
resource "aws_eks_fargate_profile" "runner" {
  count = length(var.fargate_subnet_ids) > 0 ? 1 : 0

  cluster_name           = var.cluster_name
  fargate_profile_name   = "runner-${var.name}"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution[0].arn
  subnet_ids             = var.fargate_subnet_ids
  tags                   = var.tags

  selector {
    namespace = local.namespace
  }

  depends_on = [aws_iam_role_policy_attachment.fargate_pod_execution]
}
