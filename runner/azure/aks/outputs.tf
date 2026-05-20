output "resource_group_name" {
  value = var.resource_group_name

}

output "cluster_name" {
  value = module.aks.cluster_name

}

output "k8s_access" {
  value = join("", ["az aks get-credentials --resource-group ", var.resource_group_name, " --name ", module.aks.cluster_name, " --overwrite-existing"])
}

output "k8s_workload_identity_client_id" {
  value = module.aks.runner_workload_identity_client_id
}

output "key_vault_name" {
  value = module.aks.key_vault_name
}

# Service Principal credentials for Key Vault authentication
output "runner_sp_client_id" {
  value     = module.aks.runner_sp_client_id
  sensitive = true
}

output "runner_sp_client_secret" {
  value     = module.aks.runner_sp_client_secret
  sensitive = true
}

output "runner_sp_tenant_id" {
  value = module.aks.runner_sp_tenant_id
}

output "nat_gateway_public_ip" {
  value = module.networking.nat_gateway_public_ip
}