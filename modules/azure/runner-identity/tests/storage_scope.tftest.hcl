# Run with: terraform test  (from modules/azure/runner-identity)
#
# Scope of the Storage Blob Data Contributor grant. Uses a mock provider, so no
# Azure credentials or resources are needed.

mock_provider "azurerm" {
  mock_data "azurerm_key_vault" {
    defaults = {
      id                         = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/kv-shared"
      rbac_authorization_enabled = true
    }
  }
}

variables {
  name                          = "grid"
  location                      = "uksouth"
  resource_group_name           = "rg"
  oidc_issuer_url               = "https://oidc.example.test/issuer"
  namespace                     = "bu-grid"
  service_account_name          = "runner-grid-sa"
  key_vault_name                = "kv-shared"
  key_vault_resource_group_name = "rg"
  storage_account_id            = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/staging"
}

# An existing caller who upgrades the module and sets nothing new keeps the
# account-scoped grant, so the role assignment is not replaced.
run "defaults_grant_on_the_account" {
  command = plan

  assert {
    condition     = azurerm_role_assignment.storage[0].scope == var.storage_account_id
    error_message = "Without a container name the grant should stay scoped to the storage account."
  }
}

run "container_name_scopes_the_grant_to_the_container" {
  command = plan

  variables {
    storage_container_name = "grid-staging"
  }

  assert {
    condition     = azurerm_role_assignment.storage[0].scope == "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/staging/blobServices/default/containers/grid-staging"
    error_message = "The grant should be scoped to the named container, got ${azurerm_role_assignment.storage[0].scope}."
  }

  assert {
    condition     = azurerm_role_assignment.storage[0].role_definition_name == "Storage Blob Data Contributor"
    error_message = "The role should not change with the scope."
  }
}

run "no_storage_account_grants_no_storage_access" {
  command = plan

  variables {
    storage_account_id = ""
  }

  assert {
    condition     = length(azurerm_role_assignment.storage) == 0
    error_message = "No storage grant should exist without a storage account."
  }
}

run "rejects_container_name_without_storage_account" {
  command = plan

  variables {
    storage_account_id     = ""
    storage_container_name = "grid-staging"
  }

  expect_failures = [azurerm_user_assigned_identity.runner]
}

run "rejects_uppercase_container_name" {
  command = plan

  variables {
    storage_container_name = "Grid-Staging"
  }

  expect_failures = [var.storage_container_name]
}

run "rejects_consecutive_hyphens" {
  command = plan

  variables {
    storage_container_name = "grid--staging"
  }

  expect_failures = [var.storage_container_name]
}

run "rejects_too_short_container_name" {
  command = plan

  variables {
    storage_container_name = "gr"
  }

  expect_failures = [var.storage_container_name]
}
