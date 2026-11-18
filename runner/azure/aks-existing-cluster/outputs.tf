output "cluster_name" {
  description = "The cluster the runner goes into."
  value       = var.cluster_name
}

output "namespace" {
  description = "Install the runner chart into this namespace (helm --namespace)."
  value       = local.namespace
}

output "service_account_name" {
  description = "Set as serviceAccount.name in the chart values. The runner's identity trusts only this name."
  value       = local.service_account_name
}

output "script_runner_service_account_name" {
  description = "Set as scriptRunner.serviceAccount.name in the chart values."
  value       = local.script_runner_service_account_name
}

output "workload_identity_client_id" {
  description = "Set as azure.workloadIdentity.clientId in the chart values."
  value       = module.identity.client_id
}

output "script_runner_client_id" {
  description = "Set as scriptRunner.serviceAccount.clientId in the chart values. It has the runner's storage accounts and no Key Vault."
  value       = module.script_runner_identity.client_id
}

output "key_vault_name" {
  description = "Set as dpcAgent.dpcAgent.env.defaultKeyvault in the chart values. The runner's own vault, where it reads and saves its secrets."
  value       = azurerm_key_vault.runner.name
}

output "subscription_id" {
  description = "Set as azure.subscriptionId in the chart values. The runner looks for Key Vaults and storage accounts in this subscription."
  value       = var.azure_subscription_id
}
