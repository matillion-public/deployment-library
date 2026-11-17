# Run with: terraform test  (from modules/azure/aks)
#
# Default node pool sizing against the autoscaler floor. Uses mock providers, so
# no Azure credentials or resources are needed.

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

run "defaults_pass" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.default_node_pool[0].min_count == 2
    error_message = "A zone-unaware pool should default the autoscaler floor to 2."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.default_node_pool[0].node_count == 2
    error_message = "node_count should default to 2."
  }
}

run "zones_with_matching_node_count_pass" {
  command = plan

  variables {
    node_pool_zones    = ["1", "2", "3"]
    desired_node_count = 3
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.default_node_pool[0].min_count == 3
    error_message = "The autoscaler floor should default to one node per zone."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.default_node_pool[0].node_count == 3
    error_message = "node_count should be desired_node_count."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.default_node_pool[0].max_count == 6
    error_message = "The autoscaler ceiling should default to twice desired_node_count."
  }
}

# azurerm accepts this at plan and rejects it at apply, after the rest of the
# root has been created.
run "zones_with_example_node_count_rejected" {
  command = plan

  variables {
    node_pool_zones    = ["1", "2", "3"]
    desired_node_count = 2
  }

  expect_failures = [azurerm_kubernetes_cluster.aks_cluster]
}

run "explicit_floor_above_desired_rejected" {
  command = plan

  variables {
    min_node_count     = 4
    desired_node_count = 3
  }

  expect_failures = [azurerm_kubernetes_cluster.aks_cluster]
}

run "explicit_floor_overrides_zone_default" {
  command = plan

  variables {
    node_pool_zones    = ["1", "2", "3"]
    min_node_count     = 2
    desired_node_count = 2
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.default_node_pool[0].min_count == 2
    error_message = "An explicit min_node_count should override the per-zone default."
  }
}
