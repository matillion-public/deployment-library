# Run with: terraform test  (from runner/azure/aks)
#
# The salt is not overridden here, so it is unknown at plan as on a new
# deployment. Any Key Vault name check that reads the salt is then unknown, and
# terraform test fails the run. A root test cannot list a module's check or
# resource in expect_failures, so the failing lengths are covered by the module
# tests. Uses mock providers, so no Azure credentials or resources are needed.

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
  azure_subscription_id = "00000000-0000-0000-0000-000000000002"
  azure_tenant_id       = "00000000-0000-0000-0000-000000000001"
  location              = "uksouth"
  resource_group_name   = "rg"
  tags                  = {}
  authorized_ip_ranges  = ["203.0.113.0/24"]
}

run "new_deployment_with_name_of_17_plans_without_unknown_checks" {
  command = plan

  variables {
    name = "aaaaaaaaaaaaaaaaa"
  }
}
