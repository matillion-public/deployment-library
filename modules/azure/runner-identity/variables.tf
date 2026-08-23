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

variable "key_vault_name" {
  type        = string
  description = "Name of the Key Vault holding this runner's secrets"
}

variable "key_vault_resource_group_name" {
  type        = string
  description = "Resource group of the Key Vault"
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
  description = "Grant Key Vault Secrets User across the whole vault rather than per secret. Correct when this vault belongs to a single tenant, since the vault boundary is then the tenant boundary. On a vault shared between tenants it gives the runner every other tenant's secrets — list key_vault_secret_names instead. Also the option for deployments that create secrets at runtime and cannot enumerate them at plan time."
  default     = false
}

variable "grant_vault_reader" {
  type        = bool
  description = "Grant Reader on the vault for metadata resolution. No secret values, but does expose the names of every secret in the vault."
  default     = true
}

variable "storage_account_id" {
  type        = string
  description = "Storage account to grant Storage Blob Data Contributor on. Empty grants no storage access."
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the managed identity"
  default     = {}
}
