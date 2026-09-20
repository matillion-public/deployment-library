# AWS Terraform state management

Creates the S3 bucket and DynamoDB lock table that hold Terraform state for a
deployment, plus the versioning, encryption, public-access-block and bucket policy
around them. This is a bootstrap module: it runs with local state, and everything
else then uses the backend it created.

```hcl
module "state_management" {
  source = "../../modules/aws/state-management"

  account_id = var.account_id   # the only required input

  # All optional:
  region            = var.region
  environment       = var.environment
  allowed_role_arns = [data.aws_caller_identity.current.arn]
}
```

## The names are a contract, not a cosmetic choice

Both names are also backend configuration. A Terraform backend is resolved before
any provider runs, so it cannot read them from this module at `init` time — they
have to be written into the backend block.

Take them from the `backend_config` output rather than rebuilding them from
`account_id`:

```hcl
output "backend_config" {
  value = {
    bucket         = ...
    region         = ...
    dynamodb_table = ...
    encrypt        = true
  }
}
```

`templates/backend_s3.tf.tmpl` renders `bucket` and `dynamodb_table` from that
output. Neither is reconstructed in the template, so a `resource_names` override
cannot leave the backend pointing at something that does not exist.

This used to be safe by coincidence: the template derived both names with the same
`${account_id}-terraform-states` / `-terraform-locks` expression the module used, so
they always agreed. Once the names became overridable that stopped being true.

## Renaming a deployed backend is a state migration

`bucket` is force-new on `aws_s3_bucket` and `name` is force-new on
`aws_dynamodb_table`, and the bucket holds every state file for the deployment.
Changing `resource_names.state_bucket` or `state_lock_table` on a **live** platform
is therefore not a rename — it is "create a new empty backend and abandon the old
one".

Both resources carry `prevent_destroy`, so a plan that would replace them fails
rather than proceeding. That is deliberate: the failure is much cheaper than the
alternative. To migrate on purpose:

1. `terraform state pull` from the existing backend and keep the file.
2. Remove the `prevent_destroy` blocks.
3. Apply the new names.
4. `terraform init -migrate-state`, or `terraform state push` into the new bucket.

To tear the backend down entirely, remove the `prevent_destroy` blocks first. Note
that S3 versioning is enabled, so the bucket must be emptied of all object versions
before it can be deleted.

## Naming keys

Consumed from `modules/aws/naming` (see its README):

| Key | Resource | Constraint |
|---|---|---|
| `state_bucket` | S3 bucket | globally unique, lowercase, 3–63 |
| `state_lock_table` | DynamoDB table | 3–255, accepts uppercase unlike S3 |

Leave `resource_names` unset and the module derives both from `account_id`, exactly
as it did before naming existed.

## Azure equivalent

`modules/azure/state-management` has the same shape and the same contract. The two
were fixed together — DPC-56269 for Azure, DPC-56416 here.
