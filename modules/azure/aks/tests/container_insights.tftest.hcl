# Run with: terraform test  (from modules/azure/aks)
#
# Container Insights opt-in: the Log Analytics workspace and the cluster's
# oms_agent block exist only when enable_container_insights is true. Uses mock
# providers, so no Azure credentials or resources are needed.

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
  name                 = "t"
  location             = "uksouth"
  resource_group_name  = "rg"
  subnet_ids           = ["/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/aks"]
  tags                 = {}
  random_string_salt   = "abc123"
  authorized_ip_ranges = ["203.0.113.0/24"]
}

run "defaults_create_no_workspace_and_no_oms_agent" {
  command = plan

  assert {
    condition     = length(azurerm_log_analytics_workspace.aks_log_workspace) == 0
    error_message = "No Log Analytics workspace must be created by default."
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.aks_cluster.oms_agent) == 0
    error_message = "The cluster must have no oms_agent block by default."
  }

  assert {
    condition     = output.log_analytics_workspace_id == null
    error_message = "log_analytics_workspace_id must be null by default."
  }

  assert {
    condition     = output.log_analytics_workspace_name == null
    error_message = "log_analytics_workspace_name must be null by default."
  }
}

run "enabled_creates_workspace_and_oms_agent" {
  command = plan

  variables {
    enable_container_insights = true
  }

  assert {
    condition     = length(azurerm_log_analytics_workspace.aks_log_workspace) == 1
    error_message = "enable_container_insights = true must create one Log Analytics workspace."
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.aks_cluster.oms_agent) == 1
    error_message = "enable_container_insights = true must add an oms_agent block to the cluster."
  }

  assert {
    condition     = output.log_analytics_workspace_name == "t-log-workspace-abc123"
    error_message = "The workspace must keep its generated name."
  }

  assert {
    condition     = azurerm_log_analytics_workspace.aks_log_workspace[0].sku == "PerGB2018"
    error_message = "The workspace SKU must be PerGB2018."
  }
}

run "enabled_outputs_the_workspace_id" {
  command = plan

  variables {
    enable_container_insights = true
  }

  override_resource {
    target          = azurerm_log_analytics_workspace.aks_log_workspace[0]
    override_during = plan
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/w"
    }
  }

  assert {
    condition     = output.log_analytics_workspace_id == "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/w"
    error_message = "log_analytics_workspace_id must be the workspace ID."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.oms_agent[0].log_analytics_workspace_id == "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/w"
    error_message = "oms_agent must point at the module's workspace."
  }
}

run "resource_names_override_is_kept_when_enabled" {
  command = plan

  variables {
    enable_container_insights = true
    resource_names            = { log_workspace = "custom-law" }
  }

  assert {
    condition     = output.log_analytics_workspace_name == "custom-law"
    error_message = "The log_workspace key in resource_names must still name the workspace."
  }
}
