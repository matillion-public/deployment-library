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

# Script runner connection details — printed on apply when enable_script_runner = true.
# Use these to configure a Script Pushdown component in manual mode (host + port + user + your SSH key).
output "script_runner_host" {
  description = "Host to reach the script runner over SSH (bare Container App name; the env-domain FQDN does not resolve sibling-to-sibling)"
  value       = module.container_apps.script_runner_host
}

output "script_runner_ssh_port" {
  description = "SSH port the script runner listens on"
  value       = module.container_apps.script_runner_ssh_port
}

output "script_runner_ssh_user" {
  description = "SSH user for the script runner"
  value       = module.container_apps.script_runner_ssh_user
}

output "script_runner_fqdn" {
  description = "Internal FQDN of the script runner Container App (diagnostic reference only — not routable for sibling-to-sibling SSH within the same environment; use script_runner_host for that). Null when enable_script_runner = false."
  value       = module.container_apps.script_runner_fqdn
}
