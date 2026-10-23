# Run with: terraform test  (from modules/azure/aks)
#
# Network policy engine and data plane. Uses mock providers, so no Azure
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

# azure is both the provider's default and the value it reads back from a
# cluster that never set one, so existing clusters see no change.
run "defaults_keep_the_azure_data_plane" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].network_data_plane == "azure"
    error_message = "network_data_plane must default to azure."
  }
}

run "cilium_on_overlay" {
  command = plan

  variables {
    network_plugin_mode = "overlay"
    network_policy      = "cilium"
    network_data_plane  = "cilium"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].network_policy == "cilium"
    error_message = "network_policy should be cilium."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].network_data_plane == "cilium"
    error_message = "network_data_plane should be cilium."
  }
}

run "calico_on_the_azure_data_plane" {
  command = plan

  variables {
    network_policy = "calico"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].network_policy == "calico"
    error_message = "network_policy should be calico."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].network_data_plane == "azure"
    error_message = "Calico runs on the azure data plane."
  }
}

run "rejects_cilium_policy_without_the_cilium_data_plane" {
  command = plan

  variables {
    network_plugin_mode = "overlay"
    network_policy      = "cilium"
  }

  expect_failures = [azurerm_kubernetes_cluster.aks_cluster]
}

run "rejects_the_cilium_data_plane_with_another_engine" {
  command = plan

  variables {
    network_plugin_mode = "overlay"
    network_policy      = "calico"
    network_data_plane  = "cilium"
  }

  expect_failures = [azurerm_kubernetes_cluster.aks_cluster]
}

run "rejects_the_cilium_data_plane_without_overlay" {
  command = plan

  variables {
    network_policy     = "cilium"
    network_data_plane = "cilium"
  }

  expect_failures = [azurerm_kubernetes_cluster.aks_cluster]
}

run "rejects_unknown_policy_engine" {
  command = plan

  variables {
    network_policy = "none"
  }

  expect_failures = [var.network_policy]
}

run "rejects_unknown_data_plane" {
  command = plan

  variables {
    network_data_plane = "kubenet"
  }

  expect_failures = [var.network_data_plane]
}
