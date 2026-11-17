# Run with: terraform test  (from modules/azure/runner-identity)
#
# What a runner's identity can and can't reach. Uses a mock provider, so no Azure
# credentials or resources are needed.

mock_provider "azurerm" {
  mock_data "azurerm_key_vault" {
    defaults = {
      id                         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/platform/providers/Microsoft.KeyVault/vaults/finance-a1b2c3"
      rbac_authorization_enabled = true
    }
  }
}

variables {
  name                          = "finance"
  location                      = "uksouth"
  resource_group_name           = "platform"
  oidc_issuer_url               = "https://uksouth.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/11111111-1111-1111-1111-111111111111/"
  namespace                     = "finance"
  service_account_name          = "finance-sa"
  key_vault_name                = "finance-a1b2c3"
  key_vault_resource_group_name = "platform"
}

run "identity_trusts_only_the_named_service_accounts" {
  command = plan

  variables {
    script_runner_service_account_name = "finance-script-runner-sa"
  }

  assert {
    condition = output.federated_subjects == [
      "system:serviceaccount:finance:finance-sa",
      "system:serviceaccount:finance:finance-script-runner-sa",
    ]
    error_message = "The identity must trust exactly the named service accounts, in their own namespace."
  }
}

run "vault_wide_write_is_secrets_officer_on_that_vault_only" {
  command = plan

  variables {
    grant_vault_wide_secret_write = true
  }

  assert {
    condition     = azurerm_role_assignment.vault_wide_secrets_officer[0].scope == data.azurerm_key_vault.target[0].id
    error_message = "Writing secrets must be limited to the vault the module looked up."
  }

  assert {
    condition     = azurerm_role_assignment.vault_wide_secrets_officer[0].role_definition_name == "Key Vault Secrets Officer"
    error_message = "Saving secrets needs Key Vault Secrets Officer; Secrets User is read only."
  }

  assert {
    condition     = length(azurerm_role_assignment.secret) == 0 && length(azurerm_role_assignment.vault_wide_secrets_user) == 0
    error_message = "Officer already covers reading, so no other secret role is granted."
  }

  assert {
    condition     = output.access_model == "vault-read-write"
    error_message = "The access model must say the runner can write to its vault."
  }
}

run "without_write_the_vault_stays_read_only" {
  command = plan

  variables {
    grant_vault_wide_secret_access = true
  }

  assert {
    condition     = length(azurerm_role_assignment.vault_wide_secrets_officer) == 0
    error_message = "Read access alone must not grant Key Vault Secrets Officer."
  }
}

run "no_vault_grants_no_vault_roles" {
  command = plan

  variables {
    grant_key_vault_access = false
  }

  assert {
    condition = (length(data.azurerm_key_vault.target) == 0
      && length(azurerm_role_assignment.secret) == 0
      && length(azurerm_role_assignment.vault_wide_secrets_user) == 0
      && length(azurerm_role_assignment.vault_wide_secrets_officer) == 0
    && length(azurerm_role_assignment.vault_reader) == 0)
    error_message = "An identity without a vault must get no Key Vault role, not even Reader."
  }

  assert {
    condition     = output.access_model == "none"
    error_message = "The access model must say the identity has no vault."
  }
}

run "vault_access_needs_a_vault" {
  command = plan

  variables {
    grant_key_vault_access        = false
    grant_vault_wide_secret_write = true
  }

  expect_failures = [azurerm_user_assigned_identity.runner]
}

run "storage_accounts_get_blob_data_access" {
  command = plan

  variables {
    storage_account_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/finance/providers/Microsoft.Storage/storageAccounts/financestaging"]
  }

  assert {
    condition     = azurerm_role_assignment.storage_accounts[var.storage_account_ids[0]].role_definition_name == "Storage Blob Data Contributor"
    error_message = "Each listed storage account gets blob data access."
  }

  assert {
    condition     = length(azurerm_role_assignment.storage_keys) == 0
    error_message = "Storage account keys are opt-in."
  }
}

run "storage_account_keys_are_granted_when_asked_for" {
  command = plan

  variables {
    storage_account_ids        = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/finance/providers/Microsoft.Storage/storageAccounts/financestaging"]
    grant_storage_account_keys = true
  }

  assert {
    condition     = azurerm_role_assignment.storage_keys[var.storage_account_ids[0]].role_definition_name == "Reader and Data Access"
    error_message = "With keys asked for, each listed storage account gets Reader and Data Access, so the runner can find it and sign staging SAS tokens."
  }
}

run "rejects_a_storage_account_name_for_an_id" {
  command = plan

  variables {
    storage_account_ids = ["financestaging"]
  }

  expect_failures = [var.storage_account_ids]
}

run "a_single_storage_account_keeps_its_grant" {
  command = plan

  variables {
    storage_account_id = "/subscriptions/s/resourceGroups/g/providers/Microsoft.Storage/storageAccounts/legacy"
  }

  assert {
    condition     = length(azurerm_role_assignment.storage) == 1 && length(azurerm_role_assignment.storage_accounts) == 0
    error_message = "storage_account_id keeps granting through the same resource it always has, so upgrading doesn't re-create the grant."
  }
}

run "rejects_one_storage_account_given_twice" {
  command = plan

  variables {
    storage_account_id  = "/subscriptions/s/resourceGroups/g/providers/Microsoft.Storage/storageAccounts/legacy"
    storage_account_ids = ["/subscriptions/S/resourcegroups/G/providers/microsoft.storage/storageAccounts/LEGACY"]
  }

  expect_failures = [azurerm_user_assigned_identity.runner]
}

run "vault_reader_is_granted_by_default_and_can_be_dropped" {
  command = plan

  assert {
    condition     = length(azurerm_role_assignment.vault_reader) == 1 && azurerm_role_assignment.vault_reader[0].role_definition_name == "Reader" && azurerm_role_assignment.vault_reader[0].scope == data.azurerm_key_vault.target[0].id
    error_message = "By default the identity gets Reader on its vault, so the vault shows up in the runner's vault picker."
  }
}

run "vault_reader_can_be_turned_off" {
  command = plan

  variables {
    grant_vault_reader = false
  }

  assert {
    condition     = length(azurerm_role_assignment.vault_reader) == 0
    error_message = "grant_vault_reader = false must grant no Reader role."
  }
}

run "rejects_one_storage_account_listed_twice" {
  command = plan

  variables {
    storage_account_ids = [
      "/subscriptions/s/resourceGroups/g/providers/Microsoft.Storage/storageAccounts/financestaging",
      "/subscriptions/S/resourcegroups/G/providers/microsoft.storage/storageAccounts/FINANCESTAGING",
    ]
  }

  expect_failures = [var.storage_account_ids]
}
