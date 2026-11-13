# Run with: terraform test  (from modules/azure/aks)
#
# Default node pool upgrade settings. Uses mock providers, so no Azure
# credentials or resources are needed.

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

# The values match what AKS sets on a pool created without upgrade settings,
# so the plan after an apply reports no change to the pool.
run "default_pool_declares_upgrade_settings" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.default_node_pool[0].upgrade_settings[0].max_surge == "10%"
    error_message = "upgrade_settings.max_surge must be 10%."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.default_node_pool[0].upgrade_settings[0].drain_timeout_in_minutes == 0
    error_message = "upgrade_settings.drain_timeout_in_minutes must be 0."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.default_node_pool[0].upgrade_settings[0].node_soak_duration_in_minutes == 0
    error_message = "upgrade_settings.node_soak_duration_in_minutes must be 0."
  }
}
