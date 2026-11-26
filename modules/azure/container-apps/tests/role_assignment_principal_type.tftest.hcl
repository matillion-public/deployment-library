# Run with: terraform test  (from modules/azure/container-apps)
#
# Role assignments whose principal is a user-assigned managed identity declare
# principal_type, so Azure does not look the principal up in Entra ID first.
# The deployer's Key Vault Administrator grant leaves it unset, because the
# deployer can be a user or a service principal.
# Uses a mock provider, so no Azure credentials are needed.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      object_id       = "00000000-0000-0000-0000-000000000002"
      subscription_id = "00000000-0000-0000-0000-000000000003"
    }
  }
}

variables {
  name                   = "t"
  location               = "uksouth"
  resource_group_name    = "rg-test"
  random_string_salt     = "abc123"
  subnet_ids             = ["/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/apps"]
  account_id             = "12345"
  agent_id               = "00000000-0000-0000-0000-000000000004"
  client_id              = "client-id"
  client_secret          = "client-secret"
  matillion_cloud_region = "eu1"
}

run "defaults_set_service_principal_type_on_identity_grants" {
  command = plan

  assert {
    condition = alltrue([
      azurerm_role_assignment.storage_account_contributor.principal_type == "ServicePrincipal",
      azurerm_role_assignment.storage_blob_data_contributor.principal_type == "ServicePrincipal",
      azurerm_role_assignment.key_vault_secrets_officer.principal_type == "ServicePrincipal",
      azurerm_role_assignment.key_vault_secrets_user.principal_type == "ServicePrincipal",
      azurerm_role_assignment.key_vault_reader.principal_type == "ServicePrincipal",
    ])
    error_message = "Every role assignment on the Container App managed identity should set principal_type to ServicePrincipal."
  }

  assert {
    condition = alltrue([
      length(azurerm_role_assignment.script_runner_acr_pull) == 0,
      length(azurerm_role_assignment.script_runner_storage_blob_data_reader) == 0,
      length(azurerm_role_assignment.script_runner_key_vault_secrets_user) == 0,
    ])
    error_message = "No script runner grant should be created when enable_script_runner is false."
  }
}

run "private_registry_acr_pull_sets_service_principal_type" {
  command = plan

  variables {
    container_image_url = "privateacr.azurecr.io/cloud-agent:current"
    container_acr_id    = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-acr/providers/Microsoft.ContainerRegistry/registries/privateacr"
  }

  assert {
    condition     = azurerm_role_assignment.acr_pull[0].principal_type == "ServicePrincipal"
    error_message = "The AcrPull assignment on the Container App managed identity should set principal_type to ServicePrincipal."
  }
}

run "script_runner_grants_set_service_principal_type" {
  command = plan

  variables {
    enable_script_runner          = true
    script_runner_authorized_keys = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest test"
    script_runner_acr_id          = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-test/providers/Microsoft.ContainerRegistry/registries/matillion"
  }

  assert {
    condition = alltrue([
      azurerm_role_assignment.script_runner_acr_pull[0].principal_type == "ServicePrincipal",
      azurerm_role_assignment.script_runner_storage_blob_data_reader[0].principal_type == "ServicePrincipal",
      azurerm_role_assignment.script_runner_key_vault_secrets_user[0].principal_type == "ServicePrincipal",
    ])
    error_message = "Every role assignment on the script runner identity should set principal_type to ServicePrincipal."
  }
}

# The override only applies when the configuration leaves principal_type unset.
run "deployer_grant_leaves_principal_type_unset" {
  command = plan

  override_resource {
    target          = azurerm_role_assignment.current_client_key_vault_admin[0]
    override_during = plan
    values = {
      principal_type = "User"
    }
  }

  assert {
    condition     = azurerm_role_assignment.current_client_key_vault_admin[0].principal_type == "User"
    error_message = "The deployer's Key Vault Administrator grant should not set principal_type, because the deployer can be a user or a service principal."
  }
}
