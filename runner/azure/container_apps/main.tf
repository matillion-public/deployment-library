locals {
  # Empty when naming is off, which is what every module falls back on. try() here
  # only covers module.naming being absent at count = 0 — it does not swallow the
  # module's output preconditions, so an over-length or colliding convention still
  # fails the plan through this root rather than silently reverting to default names.
  resource_names = try(module.naming[0].names, {})
}

resource "random_string" "salt" {
  length  = 6
  special = false
  upper   = false

  lifecycle {
    ignore_changes = [upper]
  }
}

# Resource naming. Skipped entirely unless the caller sets naming_tokens, so the
# default path generates exactly the names it did before.
module "naming" {
  source = "../../../modules/azure/naming"
  count  = var.naming_tokens == null ? 0 : 1

  tokens         = var.naming_tokens
  formats        = var.naming_formats
  resource_specs = var.naming_resource_specs
  overrides      = var.naming_overrides
}

module "networking" {
  source = "../../../modules/azure/networking"

  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  random_string_salt  = random_string.salt.result
  resource_names      = local.resource_names
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
  resource_names      = local.resource_names

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

  storage_account_replication_type = var.storage_account_replication_type

  enable_script_runner          = var.enable_script_runner
  script_runner_size            = var.script_runner_size
  script_runner_authorized_keys = var.script_runner_authorized_keys
  script_runner_image_url       = var.script_runner_image_url
  script_runner_acr_id          = var.script_runner_acr_id

  extension_library_location = var.extension_library_location
  external_driver_location   = var.external_driver_location
  export_logs                = var.export_logs
  proxy_protocol_http        = var.proxy_protocol_http
  proxy_protocol_https       = var.proxy_protocol_https

  tags = var.tags
}
