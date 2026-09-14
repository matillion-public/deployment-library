output "vnet_name" {
  description = "Name of the VNet the agent uses."
  value       = var.vnet_name
}

output "subnet_name" {
  description = "Name of the subnet the agent service uses."
  value       = var.subnet_name
}

output "deployer_role_definition_id" {
  description = "ID of the least-privilege deployer role definition (null when create_deployer_role = false)."
  value       = var.create_deployer_role ? azurerm_role_definition.deployer[0].role_definition_resource_id : null
}
