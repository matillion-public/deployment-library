output "job_id" {
  description = "Resource ID of the Container App Job."
  value       = azurerm_container_app_job.this.id
}

output "job_name" {
  description = "Name of the Container App Job."
  value       = azurerm_container_app_job.this.name
}

output "identity_principal_id" {
  description = "Principal (object) ID of the job's user-assigned managed identity."
  value       = azurerm_user_assigned_identity.job.principal_id
}

output "identity_client_id" {
  description = "Client ID of the job's user-assigned managed identity."
  value       = azurerm_user_assigned_identity.job.client_id
}

output "servicebus_namespace_id" {
  description = "Service Bus namespace ID the adapter consumes from (created or existing)."
  value       = local.servicebus_namespace_id
}

output "servicebus_fqdn" {
  description = "Fully-qualified Service Bus namespace, e.g. <ns>.servicebus.windows.net."
  value       = local.servicebus_fqdn
}

output "queue_name" {
  description = "Service Bus queue name the adapter consumes."
  value       = var.queue_name
}

output "mapping_table_url" {
  description = "Table Storage endpoint URL holding project mappings."
  value       = local.storage_account_url
}
