resource "random_string" "salt" {
  length  = 6
  special = false
  upper   = false

  lifecycle {
    ignore_changes = [upper]
  }
}

module "networking" {
  source = "../../../modules/azure/networking"

  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  random_string_salt  = random_string.salt.result
  tags                = var.tags

  enable_nat_gateway       = var.enable_nat_gateway
  nat_gateway_idle_timeout = var.nat_gateway_idle_timeout

  # Container Apps requires a minimum /23 subnet with delegation to Microsoft.App/environments
  # cidrsubnet("10.0.0.0/16", 7, 0) = 10.0.0.0/23  (CA environment - 512 addresses)
  # cidrsubnet("10.0.0.0/16", 8, 2) = 10.0.2.0/24  (services - 256 addresses)
  subnet_configs = [
    {
      newbits = 7
      netnum  = 0
      delegation = {
        name = "container-apps-delegation"
        service_delegation = {
          name    = "Microsoft.App/environments"
          actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
        }
      }
    },
    {
      newbits    = 8
      netnum     = 2
      delegation = null
    }
  ]
}

module "container_apps" {
  source = "../../../modules/azure/container-apps"

  name                = var.name
  random_string_salt  = random_string.salt.result
  location            = var.location
  resource_group_name = var.resource_group_name

  subnet_ids = module.networking.subnet_ids

  account_id             = var.account_id
  agent_id               = var.agent_id
  client_id              = var.client_id
  client_secret          = var.client_secret
  matillion_cloud_region = var.matillion_cloud_region
  matillion_environment  = var.matillion_environment

  container_image_url        = var.container_image_url
  container_acr_id           = var.container_acr_id
  runner_size                = var.runner_size
  workload_profile_type      = var.workload_profile_type
  workload_profile_max_count = var.workload_profile_max_count
  replica_count              = var.replica_count
  container_cpu              = var.container_cpu
  container_memory           = var.container_memory
  zone_redundancy_enabled    = var.zone_redundancy_enabled

  enable_script_runner          = var.enable_script_runner
  script_runner_size            = var.script_runner_size
  script_runner_authorized_keys = var.script_runner_authorized_keys
  script_runner_image_url       = var.script_runner_image_url
  script_runner_acr_id          = var.script_runner_acr_id

  tags = var.tags
}
