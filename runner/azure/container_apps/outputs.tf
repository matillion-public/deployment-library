output "resource_group_name" {
  value = var.resource_group_name
}

output "container_app_name" {
  description = "The name of the Azure Container App"
  value       = module.container_apps.container_app_name
}

output "container_app_environment_id" {
  description = "The ID of the Azure Container App Environment"
  value       = module.container_apps.container_app_environment_id
}

output "key_vault_name" {
  description = "The name of the Key Vault"
  value       = module.container_apps.key_vault_name
}

output "managed_identity_client_id" {
  description = "The client ID of the managed identity"
  value       = module.container_apps.managed_identity_client_id
}

output "storage_account_name" {
  description = "The name of the storage account"
  value       = module.container_apps.storage_account_name
}

output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics Workspace"
  value       = module.container_apps.log_analytics_workspace_name
}
