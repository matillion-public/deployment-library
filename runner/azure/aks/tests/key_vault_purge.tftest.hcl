# Run with: terraform test  (from runner/azure/aks)
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
      subscription_id = "00000000-0000-0000-0000-000000000002"
      object_id       = "00000000-0000-0000-0000-000000000003"
    }
  }
}

mock_provider "azuread" {}

mock_provider "http" {
  mock_data "http" {
    defaults = { response_body = "198.51.100.7" }
  }
}

variables {
  name                  = "t"
  azure_subscription_id = "00000000-0000-0000-0000-000000000002"
  azure_tenant_id       = "00000000-0000-0000-0000-000000000001"
  location              = "westeurope"
  resource_group_name   = "rg"
  tags                  = {}
  authorized_ip_ranges  = ["203.0.113.0/24"]
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
