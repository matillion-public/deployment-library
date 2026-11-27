# Run with: terraform test  (from runner/azure/container_apps)
#
# purge_key_vault_on_destroy feeds the azurerm provider's
# purge_soft_delete_on_destroy. A mock provider ignores the features block, so
# these runs cover the variable's default and null handling, not the provider
# setting itself. Uses mock providers, so no Azure credentials or resources are
# needed.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      object_id       = "00000000-0000-0000-0000-000000000002"
      subscription_id = "00000000-0000-0000-0000-000000000003"
    }
  }
}

mock_provider "azuread" {}

variables {
  name                   = "t"
  azure_subscription_id  = "00000000-0000-0000-0000-000000000003"
  azure_tenant_id        = "00000000-0000-0000-0000-000000000001"
  location               = "westeurope"
  resource_group_name    = "rg"
  tags                   = {}
  account_id             = "12345"
  agent_id               = "00000000-0000-0000-0000-000000000004"
  client_id              = "client-id"
  client_secret          = "client-secret"
  matillion_cloud_region = "eu1"
}

run "default_does_not_purge" {
  command = plan

  assert {
    condition     = var.purge_key_vault_on_destroy == false
    error_message = "purge_key_vault_on_destroy must default to false."
  }
}

run "true_plans" {
  command = plan

  variables {
    purge_key_vault_on_destroy = true
  }

  assert {
    condition     = var.purge_key_vault_on_destroy == true
    error_message = "purge_key_vault_on_destroy = true must be accepted."
  }
}

run "null_falls_back_to_default" {
  command = plan

  variables {
    purge_key_vault_on_destroy = null
  }

  assert {
    condition     = var.purge_key_vault_on_destroy == false
    error_message = "purge_key_vault_on_destroy = null must fall back to false."
  }
}
