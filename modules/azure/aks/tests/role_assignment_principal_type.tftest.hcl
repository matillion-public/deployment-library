# Run with: terraform test  (from modules/azure/aks)
#
# Role assignments whose principal is a user-assigned managed identity declare
# principal_type, so Azure does not look the principal up in Entra ID first.
# Uses mock providers, so no Azure credentials or resources are needed.

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

run "defaults_set_service_principal_type_on_identity_grants" {
  command = plan

  assert {
    condition = alltrue([
      azurerm_role_assignment.blob_storage_role.principal_type == "ServicePrincipal",
      azurerm_role_assignment.key_vault_officer_role.principal_type == "ServicePrincipal",
      azurerm_role_assignment.key_vault_role.principal_type == "ServicePrincipal",
      azurerm_role_assignment.runner_blob_storage_role[0].principal_type == "ServicePrincipal",
      azurerm_role_assignment.runner_key_vault_role[0].principal_type == "ServicePrincipal",
      azurerm_role_assignment.runner_key_vault_reader_role[0].principal_type == "ServicePrincipal",
      azurerm_role_assignment.runner_subscription_reader_role[0].principal_type == "ServicePrincipal",
    ])
    error_message = "Every role assignment on the cluster identity and the shared runner identity should set principal_type to ServicePrincipal."
  }
}

run "without_shared_runner_identity_keeps_aks_identity_type" {
  command = plan

  variables {
    create_runner_identity = false
  }

  assert {
    condition = alltrue([
      azurerm_role_assignment.blob_storage_role.principal_type == "ServicePrincipal",
      azurerm_role_assignment.key_vault_officer_role.principal_type == "ServicePrincipal",
      azurerm_role_assignment.key_vault_role.principal_type == "ServicePrincipal",
    ])
    error_message = "Every role assignment on the cluster identity should set principal_type to ServicePrincipal."
  }

  assert {
    condition = alltrue([
      length(azurerm_role_assignment.runner_blob_storage_role) == 0,
      length(azurerm_role_assignment.runner_key_vault_role) == 0,
      length(azurerm_role_assignment.runner_key_vault_reader_role) == 0,
      length(azurerm_role_assignment.runner_subscription_reader_role) == 0,
    ])
    error_message = "No shared runner identity grant should be created."
  }
}

run "workload_identity_off_keeps_aks_identity_type" {
  command = plan

  variables {
    workload_identity_enabled = false
  }

  assert {
    condition = alltrue([
      azurerm_role_assignment.blob_storage_role.principal_type == "ServicePrincipal",
      azurerm_role_assignment.key_vault_officer_role.principal_type == "ServicePrincipal",
      azurerm_role_assignment.key_vault_role.principal_type == "ServicePrincipal",
    ])
    error_message = "Every role assignment on the cluster identity should set principal_type to ServicePrincipal."
  }

  assert {
    condition = alltrue([
      length(azurerm_role_assignment.runner_blob_storage_role) == 0,
      length(azurerm_role_assignment.runner_key_vault_role) == 0,
      length(azurerm_role_assignment.runner_key_vault_reader_role) == 0,
      length(azurerm_role_assignment.runner_subscription_reader_role) == 0,
    ])
    error_message = "No shared runner identity grant should be created."
  }
}

run "without_subscription_reader_keeps_runner_identity_type" {
  command = plan

  variables {
    grant_runner_subscription_reader = false
  }

  assert {
    condition = alltrue([
      azurerm_role_assignment.runner_blob_storage_role[0].principal_type == "ServicePrincipal",
      azurerm_role_assignment.runner_key_vault_role[0].principal_type == "ServicePrincipal",
      azurerm_role_assignment.runner_key_vault_reader_role[0].principal_type == "ServicePrincipal",
    ])
    error_message = "The remaining grants on the shared runner identity should set principal_type to ServicePrincipal."
  }

  assert {
    condition     = length(azurerm_role_assignment.runner_subscription_reader_role) == 0
    error_message = "No subscription Reader assignment should be created."
  }
}
