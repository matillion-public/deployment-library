# Per-Runner Identity — Azure

One managed identity per runner deployment, federated to that runner's
Kubernetes service account. Key Vault access is granted **one secret at a
time**, read only, or across a whole vault (below). An identity can also have no
vault at all.

Equivalent modules exist for the other clouds and take the same shape:

| Cloud | Module | Identity | Per-secret grant |
|-------|--------|----------|------------------|
| Azure | `modules/azure/runner-identity` | UAMI + federated credential | Role assignment scoped to `<vault>/secrets/<name>` |
| AWS | `modules/aws/runner-identity` | IAM role + IRSA trust policy | Policy statement scoped to individual secret ARNs |
| GCP | `modules/gcp/runner-identity` | GSA + Workload Identity binding | IAM member on the individual secret |

## Why

The shared identity in `modules/azure/aks` grants `Key Vault Secrets User` at
the **vault** scope. Every runner using it can read every secret in the vault.
That is fine for one tenant and unacceptable the moment the vault also holds
another business unit's credentials.

The same weakness exists on the other clouds, which is why all three modules
landed together: `modules/gcp/gke` grants `roles/secretmanager.secretAccessor`
at the **project** level, and the ECS task role in `modules/aws/iam` attaches the
AWS-managed `SecretsManagerReadWrite` policy, which is account-wide read *and*
write.

## Requirements

**The vault must use the Azure RBAC permission model**
(`rbac_authorization_enabled = true`). This is not a preference. Legacy vault
access policies cannot express a scope below the vault, so on such a vault the
per-secret role assignments apply cleanly and grant nothing, while the runner
keeps whatever the access policies already gave it — a silent authorisation hole
rather than an error. The module reads the vault and fails the plan if the model
is wrong.

**The AKS workload identity addon must be enabled on the cluster.** An OIDC
issuer, a federated credential and a correctly annotated service account are
still not enough: without the addon the mutating webhook that injects the token
never runs, and the pod sees no credentials at all. The symptom is an IMDS
"Identity not found" 400 despite every piece of wiring looking correct. Enable it
with `az aks update --enable-workload-identity`, or `workload_identity_enabled`
in the `aks` module.

**Turn off the shared runner identity on a shared cluster.** With
`workload_identity_enabled`, the `aks` module also creates a shared runner
identity that can read every secret in the vault. Set
`create_runner_identity = false` on the `aks` module so the only identities on
the cluster are the per-tenant ones from this module.

**Secrets must exist before they are referenced.** Azure will not scope a role
assignment to a secret that is not there.

## Usage

```hcl
module "runner_identity_grid" {
  source = "../../modules/azure/runner-identity"

  name                = "grid"
  location            = var.location
  resource_group_name = var.resource_group_name

  oidc_issuer_url = module.aks.oidc_issuer_url

  namespace                         = "bu-grid"
  service_account_name              = "runner-grid-sa"
  script_runner_service_account_name = "runner-grid-script-runner-sa"

  key_vault_name                = module.aks.key_vault_name
  key_vault_resource_group_name = var.resource_group_name

  # Shared vault: name exactly what this tenant may read, and nothing else in
  # the vault is reachable. On a vault dedicated to this tenant, drop this and
  # set grant_vault_wide_secret_access = true instead — see "Choosing an
  # assignment scope" below.
  key_vault_secret_names = [
    "grid-snowflake-password",
    "grid-oauth-client-secret",
  ]

  # Shared staging account: scope blob access to this tenant's container. See
  # "Storage" below. More than one account goes in storage_account_ids instead.
  storage_account_id     = module.aks.storage_account_id
  storage_container_name = "grid"
  tags                   = var.tags
}
```

Feed the outputs straight into the tenant's Helm values:

```yaml
serviceAccount:
  name: runner-grid-sa          # module.runner_identity_grid.service_account_name
azure:
  workloadIdentity:
    enabled: true
    clientId: "<client_id>"      # module.runner_identity_grid.client_id
```

`serviceAccount.name` in the Helm values and `service_account_name` here must be
identical. The federated credential trusts that one subject; a mismatch means
the pod gets no token, and the failure surfaces as an authentication error at
runtime rather than anything at apply time.

## Verifying the isolation

The point of the module is what a runner *cannot* read, so test that rather than
the happy path. From a runner pod in one tenant's namespace:

```bash
# Should succeed — granted to this runner.
az keyvault secret show --vault-name <vault> --name grid-snowflake-password

# Should fail with Forbidden. If it succeeds, the vault is on access policies
# and the per-secret scoping is not in effect.
az keyvault secret show --vault-name <vault> --name retail-snowflake-password
```

A `Forbidden` on the second command is the result you want.

## Choosing an assignment scope

Two access models, and the right one depends on whether the vault is shared.
The module does not assume:

| Vault layout | Setting | Where isolation comes from |
|---|---|---|
| One vault shared between tenants | `key_vault_secret_names = [...]` | Per-secret RBAC |
| One vault per tenant | `grant_vault_wide_secret_access = true` | The vault boundary |
| One vault per runner, which saves secrets | `grant_vault_wide_secret_write = true` | The vault boundary |

**Vault-scoped is not a degraded mode.** Where each business unit has its own
Key Vault, the vault boundary already is the tenant boundary, and enumerating
every secret adds maintenance — a new secret means a Terraform change before the
runner can read it — without adding safety.

The combination to avoid is `grant_vault_wide_secret_access = true` on a vault
holding more than one tenant's secrets, which hands each runner all of them.
That is why it is opt-in rather than the default, and why the `access_model`
output states which model is in force so the choice is visible in plan output.

It is also the setting for deployments that read secrets created at runtime and
so cannot enumerate them at plan time.

## Secrets a runner saves itself

Both models above are read only. A runner that also saves secrets created in
Matillion needs `grant_vault_wide_secret_write = true` instead, on a vault it has
to itself. The runner calls `getSecret`, `setSecret` and `listPropertiesOfSecrets`
and nothing else. No built-in role allows `setSecret` without also allowing
delete, purge, backup and restore, so this grants Key Vault Secrets Officer. Turn
on purge protection on the vault, so anything deleted stays recoverable for the
retention period.

Azure RBAC can't limit a role to secrets whose names start with a prefix, as AWS
can. So on a vault shared with other tenants, this setting lets the runner
overwrite or delete their secrets. Give each runner that saves secrets its own
vault: `runner/azure/aks-existing-cluster` does.

## No vault

Set `grant_key_vault_access = false` and the identity gets no Key Vault role, not
even Reader. That is for a script runner, which runs code people write and so gets
an identity of its own. Setting `key_vault_secret_names`,
`grant_vault_wide_secret_access` or `grant_vault_wide_secret_write` with it fails
the plan.

It is a flag rather than an empty `key_vault_name` because the vault's name can be
unknown until apply, as when it comes from `module.aks.key_vault_name` or a random
suffix in the same configuration. What the module creates never depends on the
name, so that still plans.

## Storage

Each account in `storage_account_id` or `storage_account_ids` gets Storage Blob
Data Contributor, and nothing here grants any account not given.

- **Existing callers** keep `storage_account_id` as it is. Moving that account
  into `storage_account_ids` removes its role assignment and creates another,
  with a short gap in access, for no benefit. To add more accounts, list only the
  new ones in `storage_account_ids`.
- **New callers** can use `storage_account_ids` alone.

Giving one account in both fails the plan, comparing IDs without regard to case.

`grant_storage_account_keys = true` adds Reader and Data Access on each. That lets
the runner find the account through Azure Resource Manager, as the storage account
picker does, and read its keys: a Snowflake or Databricks load from Azure staging
is given a SAS the runner signs with an account key. Keys cover the whole account,
queues, tables and files included, and last until rotated, so leave it off for a
script runner.

### One container in a shared account

`storage_account_id` on its own grants on the **whole account**, which is right
when the account belongs to one tenant and wrong when several share it: every
runner can then read and write every other tenant's blobs.

On a shared account, give each tenant its own container and scope the grant to
it with `storage_container_name`:

| Account layout | Setting | Where isolation comes from |
|---|---|---|
| One account per tenant | `storage_account_id` only | The account boundary |
| One account shared between tenants | `storage_account_id` + `storage_container_name` | Per-container RBAC |

**The container must already exist.** The module only builds the scope
(`<account>/blobServices/default/containers/<name>`); it does not create the
container. When the container is created in the same configuration, pass its
`name` attribute rather than a literal so Terraform creates the container
before the role assignment:

```hcl
resource "azurerm_storage_container" "grid" {
  name               = "grid"
  storage_account_id = module.aks.storage_account_id
}

module "runner_identity_grid" {
  # ...
  storage_account_id     = module.aks.storage_account_id
  storage_container_name = azurerm_storage_container.grid.name
}
```

Switching an existing deployment from account scope to container scope
replaces the role assignment. Make sure the tenant's pipelines stage only to
that container first, since reads and writes anywhere else in the account are
refused afterwards.

`storage_container_name` applies to `storage_account_id` only. Accounts in
`storage_account_ids` are always granted whole, and `grant_storage_account_keys`
hands over keys that cover the whole account, so neither belongs on an account
shared between tenants.
