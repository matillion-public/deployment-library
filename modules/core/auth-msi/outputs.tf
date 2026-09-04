output "agent_identity_id" {
  description = "Resource ID of the agent managed identity. Passed to core/compute-container-apps as agent_identity_id."
  value       = azurerm_user_assigned_identity.agent_role.id
}

output "agent_identity_principal_id" {
  description = "Principal (object) ID of the agent managed identity."
  value       = azurerm_user_assigned_identity.agent_role.principal_id
}

output "agent_identity_client_id" {
  description = "Client ID of the agent managed identity."
  value       = azurerm_user_assigned_identity.agent_role.client_id
}

output "deployer_role_definition_id" {
  description = "ID of the least-privilege deployer role definition (null when create_deployer_role = false)."
  value       = var.create_deployer_role ? azurerm_role_definition.deployer[0].role_definition_resource_id : null
}
