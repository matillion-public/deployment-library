# Per-Runner Identity — Azure

One managed identity per runner deployment, federated to that runner's
Kubernetes service account, with Key Vault access granted **one secret at a
time**.

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
(`enable_rbac_authorization = true`). This is not a preference. Legacy vault
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

  storage_account_id = module.aks.storage_account_id
  tags               = var.tags
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

**Vault-scoped is not a degraded mode.** Where each business unit has its own
Key Vault, the vault boundary already is the tenant boundary, and enumerating
every secret adds maintenance — a new secret means a Terraform change before the
runner can read it — without adding safety.

The combination to avoid is `grant_vault_wide_secret_access = true` on a vault
holding more than one tenant's secrets, which hands each runner all of them.
That is why it is opt-in rather than the default, and why the `access_model`
output states which model is in force so the choice is visible in plan output.

It is also the setting for deployments that create secrets at runtime and so
cannot enumerate them at plan time.
