# Run with: terraform test  (from runner/azure/aks-existing-cluster)
#
# What one runner in a shared cluster can and can't reach. Uses a mock provider, so
# no Azure credentials or resources are needed.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000000"
      subscription_id = "11111111-1111-1111-1111-111111111111"
    }
  }
  mock_data "azurerm_kubernetes_cluster" {
    defaults = {
      location            = "uksouth"
      oidc_issuer_enabled = true
      oidc_issuer_url     = "https://uksouth.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/22222222-2222-2222-2222-222222222222/"
    }
  }
  mock_data "azurerm_key_vault" {
    defaults = { rbac_authorization_enabled = true }
  }
}

# The suffix is random and so unknown at plan; fix it to check the vault's name.
override_resource {
  target          = random_string.key_vault_suffix
  override_during = plan
  values          = { result = "a1b2c3" }
}

variables {
  name                        = "finance"
  azure_subscription_id       = "11111111-1111-1111-1111-111111111111"
  cluster_name                = "platform-shared"
  cluster_resource_group_name = "platform-rg"
}

run "names_follow_the_runner" {
  command = plan

  assert {
    condition = (output.namespace == "finance" && output.service_account_name == "finance-sa"
    && output.script_runner_service_account_name == "finance-script-runner-sa")
    error_message = "Each runner's namespace and service accounts are named after it, so runners sharing a cluster never collide."
  }

  assert {
    condition     = output.key_vault_name == "finance-a1b2c3"
    error_message = "Each runner's vault is named after it, with a random suffix to keep it unique across Azure."
  }

  assert {
    condition     = azurerm_key_vault.runner.resource_group_name == var.cluster_resource_group_name
    error_message = "Without resource_group_name, the runner's resources go in the cluster's resource group."
  }
}

run "identities_trust_only_this_runners_service_accounts" {
  command = plan

  assert {
    condition     = module.identity.federated_subjects == ["system:serviceaccount:${var.name}:${var.name}-sa"]
    error_message = "The runner's identity must trust exactly the runner's service account, in the runner's namespace."
  }

  assert {
    condition     = module.script_runner_identity.federated_subjects == ["system:serviceaccount:${var.name}:${var.name}-script-runner-sa"]
    error_message = "The script runner's identity must trust exactly the script runner's service account."
  }
}

run "runner_writes_secrets_to_its_own_vault_only" {
  command = plan

  assert {
    condition     = module.identity.access_model == "vault-read-write" && module.identity.key_vault_name == azurerm_key_vault.runner.name
    error_message = "The runner must be able to save secrets in its own vault, and no other."
  }

  assert {
    condition = (azurerm_key_vault.runner.rbac_authorization_enabled && azurerm_key_vault.runner.purge_protection_enabled
    && azurerm_key_vault.runner.soft_delete_retention_days == 7)
    error_message = "The vault must use Azure RBAC, and keep deleted secrets recoverable."
  }
}

run "script_runner_has_no_vault" {
  command = plan

  assert {
    condition     = module.script_runner_identity.access_model == "none" && module.script_runner_identity.key_vault_name == ""
    error_message = "The script runner runs people's code, so it must not get any Key Vault role."
  }
}

run "only_the_runner_gets_storage_account_keys" {
  command = plan

  variables {
    storage_account_ids = ["/subscriptions/${var.azure_subscription_id}/resourceGroups/${var.name}-rg/providers/Microsoft.Storage/storageAccounts/${var.name}staging"]
  }

  assert {
    condition     = module.identity.storage_account_keys_granted && !module.script_runner_identity.storage_account_keys_granted
    error_message = "Account keys cover the whole account and outlive the pod, so the script runner must not get them."
  }
}

run "storage_account_keys_can_be_turned_off" {
  command = plan

  variables {
    storage_account_ids        = ["/subscriptions/${var.azure_subscription_id}/resourceGroups/${var.name}-rg/providers/Microsoft.Storage/storageAccounts/${var.name}staging"]
    grant_storage_account_keys = false
  }

  assert {
    condition     = !module.identity.storage_account_keys_granted && !module.script_runner_identity.storage_account_keys_granted
    error_message = "grant_storage_account_keys = false must give neither identity account keys."
  }
}

run "vault_name_fits_key_vault_rules" {
  command = plan

  variables {
    # Collapses to "finance-analytic-emea", whose first 17 characters end in a hyphen.
    name = "finance--analytic-emea"
  }

  assert {
    condition     = output.key_vault_name == "finance-analytic-a1b2c3"
    error_message = "A long name is cut to fit 24 characters, with no doubled or trailing hyphen."
  }
}

run "refuses_a_cluster_without_an_oidc_issuer" {
  command = plan

  override_data {
    target = data.azurerm_kubernetes_cluster.this
    values = {
      location            = "uksouth"
      oidc_issuer_enabled = false
      oidc_issuer_url     = ""
    }
  }

  expect_failures = [data.azurerm_kubernetes_cluster.this]
}

run "rejects_names_azure_or_kubernetes_wont_take" {
  command = plan

  variables {
    name = "Finance_Runner"
  }

  expect_failures = [var.name]
}

run "rejects_a_name_ending_in_a_hyphen" {
  command = plan

  variables {
    name = "finance-"
  }

  expect_failures = [var.name]
}

run "rejects_the_default_namespace" {
  command = plan

  variables {
    name = "default"
  }

  expect_failures = [var.name]
}

run "rejects_a_kube_namespace" {
  command = plan

  variables {
    name = "kube-${var.cluster_name}"
  }

  expect_failures = [var.name]
}

run "rejects_a_name_another_runners_script_identity_has" {
  command = plan

  variables {
    name = "finance-scripts"
  }

  expect_failures = [var.name]
}
