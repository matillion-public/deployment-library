# Run with: terraform test  (from modules/azure/aks)
#
# Default Key Vault name and its length checks. Uses mock providers, so no
# Azure credentials or resources are needed.

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

# An unexpected check failure fails a run, so a run with no expect_failures
# also proves that no warning is raised.
run "name_of_17_keeps_the_full_salt" {
  command = plan

  variables {
    name = "aaaaaaaaaaaaaaaaa"
  }

  assert {
    condition     = azurerm_key_vault.keyvault.name == "aaaaaaaaaaaaaaaaa-abc123"
    error_message = "A 17-character name must keep all 6 salt characters in the Key Vault name."
  }
}

run "name_of_18_warns" {
  command = plan

  variables {
    name = "aaaaaaaaaaaaaaaaaa"
  }

  expect_failures = [check.key_vault_name_keeps_full_salt]
}

run "name_of_22_warns" {
  command = plan

  variables {
    name = "aaaaaaaaaaaaaaaaaaaaaa"
  }

  expect_failures = [check.key_vault_name_keeps_full_salt]
}

run "name_of_23_is_rejected" {
  command = plan

  variables {
    name = "aaaaaaaaaaaaaaaaaaaaaaa"
  }

  expect_failures = [
    azurerm_key_vault.keyvault,
    check.key_vault_name_keeps_full_salt,
  ]
}

run "name_of_24_warns" {
  command = plan

  variables {
    name = "aaaaaaaaaaaaaaaaaaaaaaaa"
  }

  expect_failures = [check.key_vault_name_keeps_full_salt]
}

run "name_with_hyphen_at_character_24_is_rejected" {
  command = plan

  variables {
    name = "aaaaaaaaaaaaaaaaaaaaaaa-aa"
  }

  expect_failures = [
    azurerm_key_vault.keyvault,
    check.key_vault_name_keeps_full_salt,
  ]
}

run "name_of_23_with_override_is_accepted" {
  command = plan

  variables {
    name           = "aaaaaaaaaaaaaaaaaaaaaaa"
    resource_names = { key_vault = "custom-kv" }
  }

  assert {
    condition     = azurerm_key_vault.keyvault.name == "custom-kv"
    error_message = "resource_names[\"key_vault\"] must replace the default Key Vault name."
  }
}

run "name_of_18_with_override_does_not_warn" {
  command = plan

  variables {
    name           = "aaaaaaaaaaaaaaaaaa"
    resource_names = { key_vault = "custom-kv" }
  }

  assert {
    condition     = azurerm_key_vault.keyvault.name == "custom-kv"
    error_message = "resource_names[\"key_vault\"] must replace the default Key Vault name."
  }
}

run "key_vault_uses_rbac_authorization" {
  command = plan

  assert {
    condition     = azurerm_key_vault.keyvault.rbac_authorization_enabled == true
    error_message = "The Key Vault must use the Azure RBAC permission model (rbac_authorization_enabled = true)."
  }
}
