# Per-runner AWS identity: one IRSA role per runner deployment, trusted by that
# runner's Kubernetes service account alone, with Secrets Manager access granted
# one secret ARN at a time.
#
# The AWS counterpart of modules/azure/runner-identity. It exists for the same
# reason: the existing ECS task role attaches the AWS-managed
# SecretsManagerReadWrite policy, which is account-wide read *and write* over
# every secret. That is not something a second business unit can be added to.

data "aws_caller_identity" "current" {}

locals {
  # The OIDC provider ARN is derived from the issuer URL so callers pass one
  # value rather than two that have to agree.
  oidc_provider_path = replace(var.oidc_issuer_url, "https://", "")
  oidc_provider_arn  = "arn:${var.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_provider_path}"

  service_account_subjects = compact([
    "system:serviceaccount:${var.namespace}:${var.service_account_name}",
    var.script_runner_service_account_name != "" ? "system:serviceaccount:${var.namespace}:${var.script_runner_service_account_name}" : "",
  ])
}

resource "aws_iam_role" "runner" {
  name = lookup(var.resource_names, "runner_role", join("-", [var.name, "runner-role"]))
  tags = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.oidc_provider_arn
      }
      Action = ["sts:AssumeRoleWithWebIdentity"]
      Condition = {
        # StringEquals throughout, deliberately — a list here matches any one
        # of the exact subjects. StringLike with a `system:serviceaccount:*`
        # pattern is the usual way IRSA scoping gets given away by accident:
        # it lets any service account in the cluster assume the role.
        StringEquals = {
          "${local.oidc_provider_path}:aud" = "sts.amazonaws.com"
          "${local.oidc_provider_path}:sub" = local.service_account_subjects
        }
      }
    }]
  })
}

# One statement per secret ARN. Read only — the runner reads credentials, it has
# no reason to be able to overwrite them.
resource "aws_iam_role_policy" "secrets" {
  count = length(var.secret_arns) > 0 ? 1 : 0

  name = lookup(var.resource_names, "runner_secrets_policy", "RunnerScopedSecretAccess")
  role = aws_iam_role.runner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
      ]
      Resource = var.secret_arns
    }]
  })
}

resource "aws_iam_role_policy" "s3" {
  count = length(var.s3_bucket_arns) > 0 ? 1 : 0

  name = lookup(var.resource_names, "runner_s3_policy", "RunnerScopedBucketAccess")
  role = aws_iam_role.runner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
      ]
      Resource = concat(
        var.s3_bucket_arns,
        [for arn in var.s3_bucket_arns : "${arn}/*"],
      )
    }]
  })
}
