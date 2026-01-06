resource "random_string" "salt" {
  length           = 6
  special          = false
  override_special = "/@£$"
}

module "networking" {
    source = "../../../modules/azure/networking"
    name = var.name
    location = var.location
    resource_group_name = var.resource_group_name
    random_string_salt = random_string.salt.result
    tags = var.tags
  
}

module "aks" {
    source = "../../../modules/azure/aks"
    name = var.name
    random_string_salt = random_string.salt.result
    
    location = var.location 
    resource_group_name = var.resource_group_name

    subnet_ids = module.networking.subnet_ids

    authorized_ip_ranges = var.authorized_ip_ranges

    desired_node_count = var.desired_node_count
    is_private_cluster = var.is_private_cluster
    
    vm_size = var.vm_size
    node_disk_size = var.node_disk_size

    workload_identity_enabled = var.workload_identity_enabled
    service_principal_enabled = var.service_principal_enabled
    service_principal_client_id = var.service_principal_client_id
    service_principal_secret = var.service_principal_secret

    tags = var.tags
    
}


# Uncomment below to generate a local kubeconfig file
# data "azurerm_kubernetes_cluster" "default" {
#   depends_on          = [module.aks] # refresh cluster state before reading
#   name                = module.aks.cluster_name
#   resource_group_name = var.resource_group_name
# }
#
# resource "local_file" "kubeconfig" {
#   depends_on   = [data.azurerm_kubernetes_cluster.default]
#   filename     = "./kubeconfig"
#   content      = data.azurerm_kubernetes_cluster.default.kube_config_raw
# }