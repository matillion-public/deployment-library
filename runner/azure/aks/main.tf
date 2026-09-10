locals {
  # Either the subnets the caller brought, or the ones the networking module made.
  subnet_ids = length(var.existing_subnet_ids) > 0 ? var.existing_subnet_ids : module.networking[0].subnet_ids
}

resource "random_string" "salt" {
  length           = 6
  special          = false
  override_special = "/@£$"
}

module "networking" {
  source = "../../../modules/azure/networking"
  # Skipped entirely when the caller supplies subnets: an enterprise landing zone
  # is usually owned by a network team, and Terraform that insists on creating its
  # own VNet cannot be run there at all.
  count = length(var.existing_subnet_ids) == 0 ? 1 : 0

  name                     = var.name
  location                 = var.location
  resource_group_name      = var.resource_group_name
  random_string_salt       = random_string.salt.result
  enable_nat_gateway       = var.enable_nat_gateway
  nat_gateway_idle_timeout = var.nat_gateway_idle_timeout
  vnet_address_space       = var.vnet_address_space
  service_endpoints        = var.service_endpoints
  tags                     = var.tags

}

module "aks" {
  source             = "../../../modules/azure/aks"
  name               = var.name
  random_string_salt = random_string.salt.result

  location            = var.location
  resource_group_name = var.resource_group_name

  subnet_ids = local.subnet_ids

  authorized_ip_ranges = var.authorized_ip_ranges

  desired_node_count = var.desired_node_count
  is_private_cluster = var.is_private_cluster

  vm_size         = var.vm_size
  node_disk_size  = var.node_disk_size
  node_pool_zones = var.node_pool_zones

  # Autoscaler bounds and cluster tier. The module defaults are sensible — a floor
  # of one node per zone, a ceiling of double desired_node_count, Standard tier —
  # but without these passthroughs a caller using this root cannot override any of
  # them, which is the whole point of having added them.
  min_node_count = var.min_node_count
  max_node_count = var.max_node_count
  sku_tier       = var.sku_tier

  storage_account_replication_type = var.storage_account_replication_type

  workload_identity_enabled   = var.workload_identity_enabled
  service_principal_enabled   = var.service_principal_enabled
  service_principal_client_id = var.service_principal_client_id
  service_principal_secret    = var.service_principal_secret

  enable_nat_gateway    = var.enable_nat_gateway
  nat_gateway_public_ip = try(module.networking[0].nat_gateway_public_ip, null)

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