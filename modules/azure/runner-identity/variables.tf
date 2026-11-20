variable "name" {
  type        = string
  description = "Name prefix for this runner's identity resources. Use something that identifies the tenant, e.g. 'grid' or 'retail', so identities are distinguishable in the portal."
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group the managed identity is created in"
}

variable "oidc_issuer_url" {
  type        = string
  description = "OIDC issuer URL of the AKS cluster. Available from the aks module as oidc_issuer_url. Requires the cluster to have oidc_issuer_enabled and workload_identity_enabled set — without the workload identity addon the token-injection webhook never runs and the pod sees no credentials however correct the rest of this wiring is."
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace this runner is deployed into"
}

variable "service_account_name" {
  type        = string
  description = "Kubernetes service account name for the runner pod. Must match serviceAccount.name in the Helm values exactly — the federated credential trusts this one subject and nothing else."
}

variable "script_runner_service_account_name" {
  type        = string
  description = "Kubernetes service account name for the script runner pod. Empty disables the second federated credential."
  default     = ""
}

variable "grant_key_vault_access" {
  type        = bool
  description = "Give the identity roles on key_vault_name. false gives it no Key Vault role at all, not even Reader, as for a script runner, which runs code people write. A flag rather than an empty key_vault_name, because a vault created in the same apply has no name yet at plan."
  default     = true
}

variable "key_vault_name" {
  type        = string
  description = "Name of the Key Vault holding this runner's secrets. Needed unless grant_key_vault_access is false. May be unknown until apply, such as module.aks.key_vault_name."
  default     = ""
}

variable "key_vault_resource_group_name" {
  type        = string
  description = "Resource group of the Key Vault. Needed unless grant_key_vault_access is false."
  default     = ""
}

variable "key_vault_secret_names" {
  type        = list(string)
  description = "Secrets in the vault this runner may read. Each gets its own role assignment scoped to that secret, so the runner cannot read anything not listed here. Use this when the vault is shared between tenants. Secrets must already exist — Azure will not scope a role assignment to a secret that is absent."
  default     = []
}

# The two access models this module supports. Which is correct depends entirely
# on whether the vault is shared, so the module does not assume one:
#
#   Shared vault      -> leave this false, list key_vault_secret_names.
#                        Isolation comes from per-secret RBAC.
#   Vault per tenant  -> set this true.
#                        Isolation comes from the vault boundary, and enumerating
#                        secrets would add maintenance without adding safety.
#
# The dangerous combination is this set true on a vault that holds more than one
# tenant's secrets, which is why it does not default that way.
variable "grant_vault_wide_secret_access" {
  type        = bool
  description = "Grant Key Vault Secrets User across the whole vault rather than per secret: read only. Correct when this vault belongs to a single tenant, since the vault boundary is then the tenant boundary. On a vault shared between tenants it gives the runner every other tenant's secrets — list key_vault_secret_names instead. Also the option for deployments that read secrets created at runtime and cannot enumerate them at plan time. To let the runner also save secrets created in Matillion, use grant_vault_wide_secret_write."
  default     = false
}

variable "grant_vault_wide_secret_write" {
  type        = bool
  description = <<-EOT
    Grant Key Vault Secrets Officer across the whole vault, so the runner can read,
    create, update and list its secrets. This is what lets a runner save secrets
    created in Matillion. No built-in role allows setSecret without also allowing
    delete, purge, backup and restore, so the runner can delete secrets too; purge
    protection on the vault keeps them recoverable. Only for a vault this runner has
    to itself: on a shared vault it could overwrite or delete every other tenant's
    secrets. Needs grant_key_vault_access.
  EOT
  default     = false
}

variable "grant_vault_reader" {
  type        = bool
  description = "Grant Reader on the vault for metadata resolution. No secret values, but does expose the names of every secret in the vault."
  default     = true
}

variable "storage_account_id" {
  type        = string
  description = "One storage account to grant Storage Blob Data Contributor on. Empty grants none. For more than one, or for account keys, use storage_account_ids."
  default     = ""
}

variable "storage_container_name" {
  type        = string
  description = "Blob container in storage_account_id to scope Storage Blob Data Contributor to. Empty, the default, grants it on the whole account. Set this when several tenants share one storage account: an account-scoped grant lets every tenant's runner read and write every other tenant's blobs. The container must already exist."
  default     = ""

  validation {
    # Azure container naming: 3-63 characters of lowercase letters, digits and
    # single hyphens, starting and ending with a letter or digit.
    condition     = var.storage_container_name == "" || (can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.storage_container_name)) && length(regexall("--", var.storage_container_name)) == 0)
    error_message = "storage_container_name must be a valid blob container name: 3-63 lowercase letters, digits and hyphens, starting and ending with a letter or digit, with no consecutive hyphens."
  }
}

variable "storage_account_ids" {
  type        = list(string)
  description = "Resource IDs of the storage accounts the runner may use for staging and data. Each gets Storage Blob Data Contributor. Empty grants no storage access."
  default     = []

  validation {
    condition     = alltrue([for id in var.storage_account_ids : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Storage/storageAccounts/[^/]+$", id))])
    error_message = "storage_account_ids must be storage account resource IDs (/subscriptions/<id>/resourceGroups/<group>/providers/Microsoft.Storage/storageAccounts/<name>), not names."
  }

  validation {
    condition     = length(var.storage_account_ids) == length(distinct([for id in var.storage_account_ids : lower(id)]))
    error_message = "storage_account_ids lists the same storage account more than once, ignoring case. Azure refuses a second identical role assignment."
  }
}

variable "grant_storage_account_keys" {
  type        = bool
  description = "Also grant Reader and Data Access on each of storage_account_ids, so the runner can find the account through Azure Resource Manager and read its keys. The runner signs the SAS for Snowflake and Databricks loads from Azure staging with a key. Keys cover the whole account, queues, tables and files included, and last until rotated, so leave this off for anything that runs code people write."
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the managed identity"
  default     = {}
}

variable "resource_names" {
  description = <<-EOT
    Resource key to explicit name, overriding the generated default. Intended to be
    fed the `names` output of modules/azure/naming, which builds them from a token
    convention. Any key left out keeps its existing generated name, so an empty map
    is exactly today's behaviour.
  EOT
  type        = map(string)
  default     = {}
}
