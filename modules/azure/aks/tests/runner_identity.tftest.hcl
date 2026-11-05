# Run with: terraform test  (from modules/azure/aks)
#
# The shared runner identity, gated separately from workload identity on the
# cluster. Uses mock providers, so no Azure credentials or resources are needed.

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

# An existing caller who upgrades the module and sets nothing new keeps the
# shared identity and every grant on it.
run "defaults_create_the_shared_runner_identity" {
  command = plan

  assert {
    condition     = length(azurerm_user_assigned_identity.runner_workload_identity) == 1
    error_message = "The shared runner identity should be created by default."
  }

  assert {
    condition = alltrue([
      length(azurerm_role_assignment.runner_blob_storage_role) == 1,
      length(azurerm_role_assignment.runner_key_vault_role) == 1,
      length(azurerm_role_assignment.runner_key_vault_reader_role) == 1,
      length(azurerm_role_assignment.runner_subscription_reader_role) == 1,
    ])
    error_message = "Every grant on the shared runner identity should be created by default."
  }

  assert {
    condition = alltrue([
      length(azurerm_federated_identity_credential.runner_federated_credential) == 1,
      length(azurerm_federated_identity_credential.script_runner_federated_credential) == 1,
    ])
    error_message = "Both federated credentials should be created by default."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.oidc_issuer_enabled && azurerm_kubernetes_cluster.aks_cluster.workload_identity_enabled
    error_message = "The OIDC issuer and workload identity should be enabled by default."
  }
}

run "shared_cluster_keeps_workload_identity_without_the_shared_identity" {
  command = plan

  variables {
    create_runner_identity = false
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.oidc_issuer_enabled && azurerm_kubernetes_cluster.aks_cluster.workload_identity_enabled
    error_message = "Per-tenant identities need the OIDC issuer and workload identity to stay enabled."
  }

  assert {
    condition = alltrue([
      length(azurerm_user_assigned_identity.runner_workload_identity) == 0,
      length(azurerm_role_assignment.runner_blob_storage_role) == 0,
      length(azurerm_role_assignment.runner_key_vault_role) == 0,
      length(azurerm_role_assignment.runner_key_vault_reader_role) == 0,
      length(azurerm_role_assignment.runner_subscription_reader_role) == 0,
      length(azurerm_federated_identity_credential.runner_federated_credential) == 0,
      length(azurerm_federated_identity_credential.script_runner_federated_credential) == 0,
    ])
    error_message = "No shared runner identity, grant or federated credential should be created."
  }

  assert {
    condition     = output.runner_workload_identity_client_id == ""
    error_message = "runner_workload_identity_client_id should be empty when no shared identity exists."
  }
}

run "workload_identity_off_creates_no_shared_identity" {
  command = plan

  variables {
    workload_identity_enabled = false
  }

  assert {
    condition     = length(azurerm_user_assigned_identity.runner_workload_identity) == 0
    error_message = "The shared runner identity needs workload identity on the cluster."
  }

  assert {
    condition     = output.runner_workload_identity_client_id == "" && output.oidc_issuer_url == ""
    error_message = "Identity outputs should be empty with workload identity off."
  }
}
