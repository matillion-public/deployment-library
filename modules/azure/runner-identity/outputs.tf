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

output "access_model" {
  description = "How this runner's Key Vault access is scoped — 'vault' when the vault belongs to one tenant, 'per-secret' when it is shared. Surfaced so the choice is visible in plan output rather than buried in a variable."
  value       = var.grant_vault_wide_secret_access ? "vault" : "per-secret"
}

output "scoped_secret_names" {
  description = "Secrets this runner can read. Under the per-secret model anything absent from this list is unreadable. Under the vault model the vault boundary is the limit and this is empty — check access_model to tell the two apart."
  value       = var.grant_vault_wide_secret_access ? [] : var.key_vault_secret_names
}
