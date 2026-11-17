# Per-Runner Identity — AWS

One IAM role per runner deployment, trusted only by that runner's Kubernetes
service account via IRSA. Secrets Manager access is granted **one secret ARN
at a time**, read only, or read and write under one name prefix (below).

The AWS member of a three-cloud set — see
`modules/azure/runner-identity/readme.md` for the shared rationale and the
comparison table.

## Why

The ECS task role in `modules/aws/iam` attaches the AWS-managed
`SecretsManagerReadWrite` policy: account-wide read *and write* over every
secret. A second business unit cannot be added to that.

## Requirements

**An IAM OIDC provider must already exist for the cluster's issuer.** Without
it, `sts:AssumeRoleWithWebIdentity` has nothing to trust and IRSA fails to issue
credentials. Create it once per cluster:

```bash
eksctl utils associate-iam-oidc-provider --cluster <name> --approve
```

## Usage

```hcl
module "runner_identity_grid" {
  source = "../../modules/aws/runner-identity"

  name            = "grid"
  oidc_issuer_url = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer

  namespace                          = "bu-grid"
  service_account_name               = "runner-grid-sa"
  script_runner_service_account_name = "runner-grid-script-runner-sa"

  # Exactly what this tenant may read. Nothing else is reachable.
  secret_arns = [
    "arn:aws:secretsmanager:eu-west-1:123456789012:secret:grid-snowflake-password-AbCdEf",
    "arn:aws:secretsmanager:eu-west-1:123456789012:secret:grid-oauth-client-secret-GhIjKl",
  ]

  s3_bucket_arns = ["arn:aws:s3:::matillion-staging-grid"]
  tags           = var.tags
}
```

Feed the outputs into the tenant's Helm values:

```yaml
serviceAccount:
  name: runner-grid-sa    # module.runner_identity_grid.service_account_name
  roleArn: "<role_arn>"   # module.runner_identity_grid.role_arn
```

`serviceAccount.name` in the Helm values and `service_account_name` here must be
identical — the trust policy names that exact subject.

Note that Secrets Manager ARNs carry a random six-character suffix. Reference
the secret resource or a data source rather than pasting the ARN, so it survives
a secret being recreated.

## Secrets a runner saves itself

`secret_arns` grants read access to secrets that already exist. A runner that also saves secrets created in Matillion needs `secret_name_prefix` instead, such as `"matillion/finance/"`. It can then read, create and update any secret whose name starts with the prefix, and nothing else. The prefix must be two segments, each ending in `/`, so no runner's prefix can contain another's: `matillion/fin/` can't match `matillion/finance/`, and `matillion/` alone is refused.

Secrets Manager can't limit `ListSecrets` to some secrets, so with a prefix the runner can list every secret's metadata in the account (name, description, tags and KMS key ID), though not their values. Keep sensitive information out of secret descriptions and tags in a shared account.

## Trust policy scoping

The trust policy uses `StringEquals` on `:sub`, with a list matching any one of
the named service accounts. This is deliberate. A `StringLike` with a pattern
such as `system:serviceaccount:*` is the usual way IRSA scoping is given away by
accident — it lets any service account in the cluster assume the role, which
removes the isolation entirely while looking like a working configuration.

## Verifying the isolation

Test what the runner *cannot* read. From a runner pod in one tenant's namespace:

```bash
# Should succeed — granted to this runner.
aws secretsmanager get-secret-value --secret-id grid-snowflake-password

# Should fail with AccessDeniedException.
aws secretsmanager get-secret-value --secret-id retail-snowflake-password
```

An `AccessDeniedException` on the second command is the result you want.
