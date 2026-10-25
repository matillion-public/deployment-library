output "cluster_name" {
  value = azurerm_kubernetes_cluster.aks_cluster.name
}

output "aks_identity_principal_id" {
  value = azurerm_user_assigned_identity.aks_identity.principal_id
}

# kube_config is sensitive in the provider schema, so these values already are.
# Declaring it lets the module be planned as a root module, which is how
# `terraform test` runs it.
output "k8s_host" {
  value     = azurerm_kubernetes_cluster.aks_cluster.kube_config.0.host
  sensitive = true
}

output "client_certificate" {
  value     = base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config.0.client_certificate)
  sensitive = true
}

output "client_key" {
  value     = base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config.0.client_key)
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config.0.cluster_ca_certificate)
  sensitive = true
}

output "runner_workload_identity_client_id" {
  value = local.create_runner_identity ? azurerm_user_assigned_identity.runner_workload_identity[0].client_id : ""
}

output "oidc_issuer_url" {
  value = var.workload_identity_enabled ? azurerm_kubernetes_cluster.aks_cluster.oidc_issuer_url : ""
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