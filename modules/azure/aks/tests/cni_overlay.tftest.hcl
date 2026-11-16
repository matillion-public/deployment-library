# Run with: terraform test  (from modules/azure/aks)
#
# Azure CNI Overlay. Uses mock providers, so no Azure credentials or resources
# are needed.

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

# An existing caller who upgrades the module and sets nothing new must render
# the network profile it always has, or the plan reimages or replaces the cluster.
run "defaults_keep_node_subnet_mode" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].network_plugin == "azure"
    error_message = "network_plugin must stay azure."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].network_plugin_mode == null
    error_message = "network_plugin_mode must be unset by default, which is node-subnet mode."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].service_cidr == "10.2.0.0/16" && azurerm_kubernetes_cluster.aks_cluster.network_profile[0].dns_service_ip == "10.2.0.10"
    error_message = "The service CIDR and DNS service IP must not move."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].load_balancer_sku == "standard" && azurerm_kubernetes_cluster.aks_cluster.network_profile[0].outbound_type == "loadBalancer"
    error_message = "The load balancer SKU and outbound type must not move."
  }
}

run "overlay_with_pod_cidr" {
  command = plan

  variables {
    network_plugin_mode = "overlay"
    pod_cidr            = "10.244.0.0/16"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].network_plugin_mode == "overlay"
    error_message = "network_plugin_mode should be overlay."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].pod_cidr == "10.244.0.0/16"
    error_message = "pod_cidr should be passed through."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].network_plugin == "azure"
    error_message = "Overlay is a mode of Azure CNI, so network_plugin must stay azure."
  }
}

run "overlay_without_pod_cidr_uses_the_aks_default" {
  command = plan

  variables {
    network_plugin_mode = "overlay"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].network_plugin_mode == "overlay"
    error_message = "network_plugin_mode should be overlay."
  }
}

run "rejects_pod_cidr_without_overlay" {
  command = plan

  variables {
    pod_cidr = "10.244.0.0/16"
  }

  expect_failures = [azurerm_kubernetes_cluster.aks_cluster]
}

run "rejects_unknown_plugin_mode" {
  command = plan

  variables {
    network_plugin_mode = "dynamic"
  }

  expect_failures = [var.network_plugin_mode]
}

run "rejects_invalid_pod_cidr" {
  command = plan

  variables {
    network_plugin_mode = "overlay"
    pod_cidr            = "10.244.0.0"
  }

  expect_failures = [var.pod_cidr]
}

run "rejects_pod_cidr_with_host_bits" {
  command = plan

  variables {
    network_plugin_mode = "overlay"
    pod_cidr            = "10.244.1.5/16"
  }

  expect_failures = [var.pod_cidr]
}

run "rejects_ipv6_pod_cidr" {
  command = plan

  variables {
    network_plugin_mode = "overlay"
    pod_cidr            = "fd12:3456:789a::/64"
  }

  expect_failures = [var.pod_cidr]
}
