# Run with: terraform test  (from modules/azure/container-apps)
#
# Default Key Vault name and its length checks. Uses a mock provider, so no
# Azure credentials or resources are needed. Names of 22 or more characters
# override the Container App name, since the default one is limited to 32
# characters and would fail the plan first.

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

# An unexpected check failure fails a run, so a run with no expect_failures
# also proves that no warning is raised.
run "name_of_5_keeps_the_full_salt" {
  command = plan

  variables {
    name = "aaaaa"
  }

  assert {
    condition     = azurerm_key_vault.keyvault.name == "aaaaa-kv-abc123"
    error_message = "A 5-character name must keep all 6 salt characters in the Key Vault name."
  }
}

run "name_of_14_keeps_the_full_salt" {
  command = plan

  variables {
    name = "aaaaaaaaaaaaaa"
  }

  assert {
    condition     = azurerm_key_vault.keyvault.name == "aaaaaaaaaaaaaa-kv-abc123"
    error_message = "A 14-character name must keep all 6 salt characters in the Key Vault name."
  }
}

run "name_of_15_warns" {
  command = plan

  variables {
    name = "aaaaaaaaaaaaaaa"
  }

  expect_failures = [check.key_vault_name_keeps_full_salt]
}

run "name_of_19_warns" {
  command = plan

  variables {
    name = "aaaaaaaaaaaaaaaaaaa"
  }

  expect_failures = [check.key_vault_name_keeps_full_salt]
}

run "name_of_20_is_rejected" {
  command = plan

  variables {
    name = "aaaaaaaaaaaaaaaaaaaa"
  }

  expect_failures = [
    azurerm_key_vault.keyvault,
    check.key_vault_name_keeps_full_salt,
  ]
}

run "name_of_21_warns" {
  command = plan

  variables {
    name = "aaaaaaaaaaaaaaaaaaaaa"
  }

  expect_failures = [check.key_vault_name_keeps_full_salt]
}

run "name_of_23_is_rejected" {
  command = plan

  variables {
    name           = "aaaaaaaaaaaaaaaaaaaaaaa"
    resource_names = { container_app = "app" }
  }

  expect_failures = [
    azurerm_key_vault.keyvault,
    check.key_vault_name_keeps_full_salt,
  ]
}

run "name_of_40_warns" {
  command = plan

  variables {
    name           = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    resource_names = { container_app = "app" }
  }

  expect_failures = [check.key_vault_name_keeps_full_salt]
}

run "name_with_hyphen_at_24_is_rejected" {
  command = plan

  variables {
    name           = "aaaaaaaaaaaaaaaaaaaaaaa-aaaaaaaaaaaaaaaa"
    resource_names = { container_app = "app" }
  }

  expect_failures = [
    azurerm_key_vault.keyvault,
    check.key_vault_name_keeps_full_salt,
  ]
}

run "name_of_20_with_override_is_accepted" {
  command = plan

  variables {
    name           = "aaaaaaaaaaaaaaaaaaaa"
    resource_names = { key_vault = "custom-kv", container_app = "app" }
  }

  assert {
    condition     = azurerm_key_vault.keyvault.name == "custom-kv"
    error_message = "resource_names[\"key_vault\"] must replace the default Key Vault name."
  }
}

run "name_of_40_with_override_is_accepted" {
  command = plan

  variables {
    name           = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    resource_names = { key_vault = "custom-kv", container_app = "app" }
  }

  assert {
    condition     = azurerm_key_vault.keyvault.name == "custom-kv"
    error_message = "resource_names[\"key_vault\"] must replace the default Key Vault name."
  }
}
