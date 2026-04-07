output "container_app_name" {
  description = "The name of the Azure Container App"
  value       = azurerm_container_app.app.name
}

output "container_app_environment_id" {
  description = "The ID of the Azure Container App Environment"
  value       = azurerm_container_app_environment.env.id
}

output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.log_analytics.id
}

output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.log_analytics.name
}

output "key_vault_name" {
  description = "The name of the Key Vault"
  value       = azurerm_key_vault.keyvault.name
}

output "managed_identity_client_id" {
  description = "The client ID of the managed identity for the Container App"
  value       = azurerm_user_assigned_identity.managed_identity.client_id
}

output "storage_account_name" {
  description = "The name of the storage account"
  value       = azurerm_storage_account.storage.name
}
