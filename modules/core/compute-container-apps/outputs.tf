output "agent_service_id" {
  description = "ID of the agent container app. Passed to addon modules to establish the depends-on-agent_service ordering."
  value       = azurerm_container_app.agent_service.id
}

output "agent_service_name" {
  description = "Name of the agent container app (\"{deployment_name}-agent\")."
  value       = azurerm_container_app.agent_service.name
}

output "agent_fqdn" {
  description = "Ingress FQDN of the agent container app (null when ingress is disabled)."
  value       = azurerm_container_app.agent_service.latest_revision_fqdn
}

output "deployer_role_definition_id" {
  description = "ID of the least-privilege deployer role definition (null when create_deployer_role = false)."
  value       = var.create_deployer_role ? azurerm_role_definition.deployer[0].role_definition_resource_id : null
}
