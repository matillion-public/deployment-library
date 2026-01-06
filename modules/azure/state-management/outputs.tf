# Outputs for Azure State Management Module

output "resource_group_name" {
  description = "Name of the resource group containing state management resources"
  value       = azurerm_resource_group.state_management.name
}

output "storage_account_name" {
  description = "Name of the storage account for Terraform state"
  value       = azurerm_storage_account.terraform_state.name
}

output "storage_container_name" {
  description = "Name of the storage container for state files"
  value       = azurerm_storage_container.terraform_state.name
}

output "storage_account_id" {
  description = "ID of the storage account for Terraform state"
  value       = azurerm_storage_account.terraform_state.id
}

output "backend_config" {
  description = "Backend configuration for Terraform"
  value = {
    resource_group_name  = azurerm_resource_group.state_management.name
    storage_account_name = azurerm_storage_account.terraform_state.name
    container_name       = azurerm_storage_container.terraform_state.name
  }
}