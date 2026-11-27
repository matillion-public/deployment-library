# Run with: terraform test  (from modules/azure/aks)
#
# Key Vault secrets provider opt-in: the cluster's key_vault_secrets_provider
# block exists only when enable_key_vault_secrets_provider is true, and then
# always with secret rotation on. Uses mock providers, so no Azure credentials
# or resources are needed.

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

run "defaults_add_no_secrets_provider" {
  command = plan

  assert {
    condition     = length(azurerm_kubernetes_cluster.aks_cluster.key_vault_secrets_provider) == 0
    error_message = "The cluster must have no key_vault_secrets_provider block by default."
  }
}

run "enabled_adds_secrets_provider_with_rotation" {
  command = plan

  variables {
    enable_key_vault_secrets_provider = true
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.aks_cluster.key_vault_secrets_provider) == 1
    error_message = "enable_key_vault_secrets_provider = true must add a key_vault_secrets_provider block."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.key_vault_secrets_provider[0].secret_rotation_enabled == true
    error_message = "Secret rotation must be on, or rotated Key Vault values never reach the synced Secret."
  }
}
