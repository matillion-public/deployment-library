# Run with: terraform test  (from runner/azure/aks)
#
# enable_container_insights reaches the cluster through this root. The
# assertions read module.aks outputs because a root test cannot read resources
# inside a child module. Uses mock providers, so no Azure credentials or
# resources are needed.

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

run "defaults_create_no_workspace" {
  command = plan

  assert {
    condition     = module.aks.log_analytics_workspace_id == null
    error_message = "No Log Analytics workspace must be created by default."
  }
}

run "enabled_is_passed_through" {
  command = plan

  variables {
    enable_container_insights = true
  }

  assert {
    condition     = module.aks.log_analytics_workspace_name == "t-log-workspace-abc123"
    error_message = "enable_container_insights = true must create the workspace."
  }
}
