output "trigger_storage_account_id" {
  description = "ID of the trigger storage account. Feed to PR #119's queue-adapter-job (existing_storage_account_id) to compose the consumer on top."
  value       = azurerm_storage_account.trigger_storage_account.id
}

output "trigger_storage_account_name" {
  description = "Name of the trigger storage account."
  value       = azurerm_storage_account.trigger_storage_account.name
}

output "trigger_queue_name" {
  description = "Name of the trigger storage queue."
  value       = azurerm_storage_queue.trigger_queue.name
}

output "trigger_queue_url" {
  description = "Queue service endpoint of the trigger storage account."
  value       = azurerm_storage_account.trigger_storage_account.primary_queue_endpoint
}

output "trigger_role_assignment_id" {
  description = "ID of the role assignment granting the agent identity queue-message access."
  value       = azurerm_role_assignment.trigger_role_assignment.id
}
