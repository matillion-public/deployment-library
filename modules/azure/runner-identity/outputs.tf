output "client_id" {
  description = "Client ID of the runner's managed identity. Set this as azure.workloadIdentity.clientId in the Helm values."
  value       = azurerm_user_assigned_identity.runner.client_id
}

output "principal_id" {
  description = "Principal (object) ID of the runner's managed identity, for additional role assignments made outside this module."
  value       = azurerm_user_assigned_identity.runner.principal_id
}

output "identity_id" {
  description = "Resource ID of the runner's managed identity"
  value       = azurerm_user_assigned_identity.runner.id
}

output "service_account_name" {
  description = "Kubernetes service account this identity is federated to. Set this as serviceAccount.name in the Helm values — the two must match or the pod gets no token."
  value       = var.service_account_name
}

output "federated_subjects" {
  description = "Kubernetes service accounts this identity trusts, as system:serviceaccount:<namespace>:<name>. A pod running as any other service account gets no token for it."
  value       = concat([azurerm_federated_identity_credential.runner.subject], azurerm_federated_identity_credential.script_runner[*].subject)
}

output "storage_account_keys_granted" {
  description = "Whether this identity can read the keys of the storage accounts it was given."
  value       = length(azurerm_role_assignment.storage_keys) > 0
}

output "key_vault_name" {
  description = "The vault this identity has roles on. Empty when it has no Key Vault access."
  value       = var.grant_key_vault_access ? var.key_vault_name : ""
}

output "access_model" {
  description = "How this runner's Key Vault access is scoped — 'vault-read-write' when it can save secrets in a vault it has to itself, 'vault' when it can read a vault that belongs to one tenant, 'per-secret' when the vault is shared, 'none' with no vault. Surfaced so the choice is visible in plan output rather than buried in a variable."
  value = (
    !var.grant_key_vault_access ? "none" :
    var.grant_vault_wide_secret_write ? "vault-read-write" :
    var.grant_vault_wide_secret_access ? "vault" : "per-secret"
  )
}

output "scoped_secret_names" {
  description = "Secrets this runner can read. Under the per-secret model anything absent from this list is unreadable. Under the vault models the vault boundary is the limit and this is empty — check access_model to tell them apart."
  value       = var.grant_key_vault_access && !var.grant_vault_wide_secret_access && !var.grant_vault_wide_secret_write ? var.key_vault_secret_names : []
}
