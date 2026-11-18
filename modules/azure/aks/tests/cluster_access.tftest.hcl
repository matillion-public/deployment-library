# Run with: terraform test  (from modules/azure/aks)
#
# Entra ID integration, local accounts and the kube_config outputs. Uses mock
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

# No Entra block and local accounts on is what existing clusters have.
run "defaults_have_no_entra_integration_and_local_accounts_enabled" {
  command = plan

  assert {
    condition     = length(azurerm_kubernetes_cluster.aks_cluster.azure_active_directory_role_based_access_control) == 0
    error_message = "Entra ID integration must be off by default."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.local_account_disabled == false
    error_message = "Local accounts must stay enabled by default."
  }
}

run "rbac_adds_the_block_with_the_group_ids" {
  command = plan

  variables {
    azure_rbac_enabled     = true
    admin_group_object_ids = ["11111111-1111-1111-1111-111111111111"]
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.azure_active_directory_role_based_access_control[0].azure_rbac_enabled == true
    error_message = "azure_rbac_enabled should be set in the Entra block."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.azure_active_directory_role_based_access_control[0].admin_group_object_ids == tolist(["11111111-1111-1111-1111-111111111111"])
    error_message = "admin_group_object_ids should be passed to the Entra block."
  }
}

run "rbac_accepts_an_empty_group_list" {
  command = plan

  variables {
    azure_rbac_enabled = true
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.aks_cluster.azure_active_directory_role_based_access_control) == 1
    error_message = "The Entra block should exist with no admin groups."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.azure_active_directory_role_based_access_control[0].azure_rbac_enabled == true
    error_message = "azure_rbac_enabled should be set in the Entra block."
  }
}

run "local_accounts_can_be_disabled_with_rbac" {
  command = plan

  variables {
    azure_rbac_enabled     = true
    local_account_disabled = true
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.local_account_disabled == true
    error_message = "local_account_disabled should be true."
  }
}

run "rejects_disabling_local_accounts_without_rbac" {
  command = plan

  variables {
    local_account_disabled = true
  }

  expect_failures = [azurerm_kubernetes_cluster.aks_cluster]
}

run "rejects_groups_without_rbac" {
  command = plan

  variables {
    admin_group_object_ids = ["11111111-1111-1111-1111-111111111111"]
  }

  expect_failures = [azurerm_kubernetes_cluster.aks_cluster]
}

run "rejects_a_malformed_group_id" {
  command = plan

  variables {
    azure_rbac_enabled     = true
    admin_group_object_ids = ["not-a-guid"]
  }

  expect_failures = [var.admin_group_object_ids]
}

# The outputs are read during plan here: with apply, the mock provider's
# generated ids fail the Key Vault role assignment's scope parsing.
run "outputs_are_empty_when_the_provider_returns_no_kube_config" {
  command = plan

  variables {
    azure_rbac_enabled     = true
    local_account_disabled = true
  }

  override_resource {
    target          = azurerm_kubernetes_cluster.aks_cluster
    override_during = plan
    values          = { kube_config = [] }
  }

  assert {
    condition     = output.k8s_host == "" && output.client_certificate == "" && output.client_key == "" && output.cluster_ca_certificate == ""
    error_message = "The kube_config outputs should be empty strings when the provider returns no kube_config."
  }
}

run "outputs_decode_the_kube_config_when_local_accounts_are_enabled" {
  command = plan

  override_resource {
    target          = azurerm_kubernetes_cluster.aks_cluster
    override_during = plan
    values = {
      kube_config = [{
        host                   = "https://h"
        client_certificate     = "Y2VydA=="
        client_key             = "a2V5"
        cluster_ca_certificate = "Y2E="
        username               = "u"
        password               = "p"
      }]
    }
  }

  assert {
    condition     = output.k8s_host == "https://h"
    error_message = "k8s_host should be the kube_config host."
  }

  assert {
    condition     = output.client_certificate == "cert"
    error_message = "client_certificate should be the decoded certificate."
  }

  assert {
    condition     = output.client_key == "key"
    error_message = "client_key should be the decoded key."
  }

  assert {
    condition     = output.cluster_ca_certificate == "ca"
    error_message = "cluster_ca_certificate should be the decoded CA certificate."
  }
}
