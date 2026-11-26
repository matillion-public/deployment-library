output "cluster_name" {
  value = azurerm_kubernetes_cluster.aks_cluster.name
}

output "aks_identity_principal_id" {
  value = azurerm_user_assigned_identity.aks_identity.principal_id
}

# kube_config is sensitive in the provider schema, so these values already are.
# Declaring it lets the module be planned as a root module, which is how
# `terraform test` runs it. Each returns "" when the provider returns no usable
# kube_config, which is the case with local accounts disabled.
output "k8s_host" {
  value     = try(azurerm_kubernetes_cluster.aks_cluster.kube_config[0].host, "")
  sensitive = true
}

output "client_certificate" {
  value     = try(base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config[0].client_certificate), "")
  sensitive = true
}

output "client_key" {
  value     = try(base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config[0].client_key), "")
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = try(base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config[0].cluster_ca_certificate), "")
  sensitive = true
}

output "runner_workload_identity_client_id" {
  value = local.create_runner_identity ? azurerm_user_assigned_identity.runner_workload_identity[0].client_id : ""
}

output "runner_federated_credential_subject" {
  description = "Subject of the runner federated credential, or empty when the shared runner identity is not created."
  value       = local.create_runner_identity ? azurerm_federated_identity_credential.runner_federated_credential[0].subject : ""
}

output "oidc_issuer_url" {
  value = var.workload_identity_enabled ? azurerm_kubernetes_cluster.aks_cluster.oidc_issuer_url : ""
}

output "network_policy" {
  description = "Network policy engine configured on the cluster (azure, calico, cilium), or null if none."
  value       = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].network_policy
}

output "network_data_plane" {
  description = "Pod networking data plane of the cluster (azure or cilium)."
  value       = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].network_data_plane
}

output "network_plugin_mode" {
  description = "Azure CNI plugin mode (overlay), or null for node-subnet mode."
  value       = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].network_plugin_mode
}

output "azure_rbac_enabled" {
  description = "Whether Entra ID integration with Azure RBAC for Kubernetes is enabled on the cluster."
  value       = length(azurerm_kubernetes_cluster.aks_cluster.azure_active_directory_role_based_access_control) > 0
}

output "admin_group_object_ids" {
  description = "Entra ID group object IDs bound to cluster-admin, or an empty list when Entra integration is off."
  value       = try(azurerm_kubernetes_cluster.aks_cluster.azure_active_directory_role_based_access_control[0].admin_group_object_ids, [])
}

output "local_account_disabled" {
  description = "Whether the cluster's local accounts (the admin kubeconfig) are disabled."
  value       = azurerm_kubernetes_cluster.aks_cluster.local_account_disabled
}

output "key_vault_name" {
  value = azurerm_key_vault.keyvault.name
}

output "key_vault_id" {
  value = azurerm_key_vault.keyvault.id
}

# Feeds modules/azure/runner-identity, which grants each per-tenant identity
# access to the staging account without going through the shared identity.
output "storage_account_id" {
  value = azurerm_storage_account.stagging.id
}

# Service Principal outputs for Key Vault authentication
output "runner_sp_client_id" {
  value     = var.service_principal_enabled ? var.service_principal_client_id : ""
  sensitive = true
}

output "runner_sp_client_secret" {
  value     = var.service_principal_enabled ? var.service_principal_secret : ""
  sensitive = true
}

output "runner_sp_tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace Container Insights writes to, or null when enable_container_insights is false."
  value       = one(azurerm_log_analytics_workspace.aks_log_workspace[*].id)
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace Container Insights writes to, or null when enable_container_insights is false."
  value       = one(azurerm_log_analytics_workspace.aks_log_workspace[*].name)
}
