output "cluster_name" {
  value = azurerm_kubernetes_cluster.aks_cluster.name
}

output "aks_identity_principal_id" {
  value = azurerm_user_assigned_identity.aks_identity.principal_id
}

output "k8s_host" {
  value = azurerm_kubernetes_cluster.aks_cluster.kube_config.0.host
}

output "client_certificate" {
  value = base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config.0.client_certificate) 
}

output "client_key" {
  value = base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config.0.client_key) 

}

output "cluster_ca_certificate" {
  value = base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config.0.cluster_ca_certificate)  
  
}

output "agent_workload_identity_client_id" {
  value = var.workload_identity_enabled ? azurerm_user_assigned_identity.agent_workload_identity[0].client_id : ""
}

output "oidc_issuer_url" {
  value = var.workload_identity_enabled ? azurerm_kubernetes_cluster.aks_cluster.oidc_issuer_url : ""
}

output "key_vault_name" {
  value = azurerm_key_vault.keyvault.name
}

# Service Principal outputs for Key Vault authentication
output "agent_sp_client_id" {
  value = var.service_principal_enabled ? var.service_principal_client_id : ""
  sensitive = true
}

output "agent_sp_client_secret" {
  value = var.service_principal_enabled ? var.service_principal_secret : ""
  sensitive = true
}

output "agent_sp_tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}