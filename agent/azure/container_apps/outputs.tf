output "container_app_name" {
  description = "The name of the Azure Container App"
  value       = azurerm_container_app.container_app.name
}

output "container_app_environment_id" {
  description = "The ID of the Azure Container App Environment"
  value       = azurerm_container_app_environment.container_app_env.id
}

output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.log_analytics.id
}

output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics Workspace"
  value       = var.log_analytics_workspace_name
}
