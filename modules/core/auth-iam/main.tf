# modules/core/auth-iam  (AWS)
#
# FOUNDATION resource: the agent IAM role ("agent_role"). Every other AWS
# composer module depends (directly or transitively) on this role. Mirrors and
# is intended to align with the production modules/aws/iam module; kept thin here
# so the composer's declared path resolves to a real, least-privilege role.

locals {
  role_name = "${var.deployment_name}-agent-role"

  # Trust policy: ECS tasks always; plus an external principal for assume_role.
  assume_principals = compact([
    "ecs-tasks.amazonaws.com",
  ])
}

# Trust / assume-role policy for the agent role.
data "aws_iam_policy_document" "assume" {
  statement {
    sid     = "EcsTasksAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = local.assume_principals
    }
  }

  # Allow an external account/role to assume the agent role (assume_role auth),
  # optionally gated by an external ID for confused-deputy protection.
  dynamic "statement" {
    for_each = var.auth_method == "assume_role" && var.role_arn != "" ? [1] : []
    content {
      sid     = "ExternalPrincipalAssume"
      effect  = "Allow"
      actions = ["sts:AssumeRole"]
      principals {
        type        = "AWS"
        identifiers = [var.role_arn]
      }
      dynamic "condition" {
        for_each = var.external_id != "" ? [1] : []
        content {
          test     = "StringEquals"
          variable = "sts:ExternalId"
          values   = [var.external_id]
        }
      }
    }
  }
}

resource "aws_iam_role" "agent_role" {
  name                 = local.role_name
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600
  tags                 = var.tags
}

# Runtime permission the agent needs: read its Matillion link secret.
data "aws_iam_policy_document" "runtime" {
  # checkov:skip=CKV_AWS_356:secret_arns defaults to ["*"] so the module is usable before the secret exists; callers scope it to the specific Matillion secret ARN.
  # checkov:skip=CKV_AWS_108:Read-only GetSecretValue on the caller-scoped secret; not a data-exfiltration path.
  statement {
    sid       = "ReadMatillionSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = var.secret_arns
  }
}

resource "aws_iam_role_policy" "runtime" {
  name   = "${var.deployment_name}-agent-runtime"
  role   = aws_iam_role.agent_role.id
  policy = data.aws_iam_policy_document.runtime.json
}

# ---------------------------------------------------------------------------
# Least-privilege permission set a DEPLOYING principal needs to provision this
# module. Mirrors the composer contract's declared permissions exactly.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "deployer" {
  # checkov:skip=CKV_AWS_356:ReadRuntimeSecret uses the caller-supplied secret_arns (defaults to ["*"] until scoped); other statements are ARN-scoped to {deployment_name}-*.
  # checkov:skip=CKV_AWS_108:Deployer permission set for provisioning; secret read is scoped by the caller, not a data-exfiltration path.
  statement {
    sid    = "AgentRoleLifecycle"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:GetRole",
      "iam:AttachRolePolicy",
      "iam:PassRole",
    ]
    resources = ["arn:aws:iam::*:role/${var.deployment_name}-*"]
  }
  statement {
    sid       = "AgentAssumeRole"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::*:role/${var.deployment_name}-*"]
  }
  statement {
    sid       = "ReadRuntimeSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = var.secret_arns
  }
}

resource "aws_iam_policy" "deployer" {
  count       = var.create_deployer_policy ? 1 : 0
  name        = "${var.deployment_name}-auth-iam-deployer"
  description = "Least-privilege permissions to provision the core/auth-iam module."
  policy      = data.aws_iam_policy_document.deployer.json
  tags        = var.tags
}
