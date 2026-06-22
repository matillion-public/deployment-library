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

output "script_runner_host" {
  description = "Bare Container App name to use as the SSH host from a sibling Container App within the same environment. Null when enable_script_runner = false."
  value       = var.enable_script_runner ? azurerm_container_app.script_runner[0].name : null
}

output "script_runner_ssh_port" {
  description = "SSH port the script runner listens on (non-root sshd uses the unprivileged 2222). Null when enable_script_runner = false."
  value       = var.enable_script_runner ? 2222 : null
}

output "script_runner_ssh_user" {
  description = "SSH user for the script runner image. Null when enable_script_runner = false."
  value       = var.enable_script_runner ? "mtln" : null
}

output "script_runner_fqdn" {
  description = "Internal FQDN of the script runner Container App (diagnostic reference only — not routable for sibling-to-sibling SSH within the same environment; use script_runner_host for that). Null when enable_script_runner = false."
  value       = var.enable_script_runner ? azurerm_container_app.script_runner[0].ingress[0].fqdn : null
}
