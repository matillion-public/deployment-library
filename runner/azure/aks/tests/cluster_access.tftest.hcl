# Run with: terraform test  (from runner/azure/aks)
#
# The cluster access inputs reach the cluster through this root. The assertions
# read module.aks outputs because a root test cannot read resources inside a
# child module. Uses mock providers, so no Azure credentials or resources are
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

override_resource {
  target          = random_string.salt
  override_during = plan
  values          = { result = "abc123" }
}

variables {
  name                  = "t"
  azure_subscription_id = "00000000-0000-0000-0000-000000000002"
  azure_tenant_id       = "00000000-0000-0000-0000-000000000001"
  location              = "uksouth"
  resource_group_name   = "rg"
  tags                  = {}
  authorized_ip_ranges  = ["203.0.113.0/24"]
}

run "defaults_leave_access_unchanged" {
  command = plan

  assert {
    condition     = module.aks.azure_rbac_enabled == false
    error_message = "Entra ID integration must be off by default."
  }

  assert {
    condition     = module.aks.local_account_disabled == false
    error_message = "Local accounts must stay enabled by default."
  }

  assert {
    condition     = length(module.aks.admin_group_object_ids) == 0
    error_message = "admin_group_object_ids must default to an empty list."
  }
}

run "entra_inputs_are_passed_through" {
  command = plan

  variables {
    azure_rbac_enabled     = true
    admin_group_object_ids = ["11111111-1111-1111-1111-111111111111"]
    local_account_disabled = true
  }

  assert {
    condition     = module.aks.azure_rbac_enabled == true
    error_message = "azure_rbac_enabled should reach the cluster."
  }

  assert {
    condition     = tolist(module.aks.admin_group_object_ids) == tolist(["11111111-1111-1111-1111-111111111111"])
    error_message = "admin_group_object_ids should reach the cluster."
  }

  assert {
    condition     = module.aks.local_account_disabled == true
    error_message = "local_account_disabled should reach the cluster."
  }
}
