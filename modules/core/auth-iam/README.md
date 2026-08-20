# core/auth-iam (AWS)

**FOUNDATION** module. Creates the agent IAM role (`{deployment_name}-agent-role`)
that every other AWS composer module depends on. Aligns with the production
[`modules/aws/iam`](../../aws/iam) module; kept thin so the composer's declared
`iac.terraform` path resolves to a real, least-privilege role.

Declares:
- `agent_role` — `aws_iam_role` with a trust policy for ECS tasks and (for
  `assume_role` auth) an external principal gated by an optional `external_id`.
- A runtime inline policy granting `secretsmanager:GetSecretValue` on the
  Matillion link secret only.
- A least-privilege **deployer** managed policy mirroring the composer's declared
  permission set: `iam:CreateRole/GetRole/AttachRolePolicy/PassRole`,
  `sts:AssumeRole`, `secretsmanager:GetSecretValue`.

## Inputs
`deployment_name`, `auth_method` (`access_key`|`assume_role`), `role_arn`,
`external_id`, `secret_arns`, `create_deployer_policy`, `tags`.

## Outputs
`agent_role_arn`, `agent_role_name`, `auth_method`, `deployer_policy_json`,
`deployer_policy_arn`.
