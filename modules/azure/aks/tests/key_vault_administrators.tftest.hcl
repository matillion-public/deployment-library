# Run with: terraform test  (from modules/azure/aks)
#
# Who is granted Key Vault Administrator on the vault. Uses mock providers, so
# no Azure credentials or resources are needed.

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

run "unset_grants_the_current_client" {
  command = plan

  assert {
    condition     = length(azurerm_role_assignment.current_client_key_vault_admin) == 1
    error_message = "With the variable unset, the identity running Terraform should be granted."
  }

  assert {
    condition     = azurerm_role_assignment.current_client_key_vault_admin[0].principal_id == "00000000-0000-0000-0000-000000000003"
    error_message = "The grant should go to the object ID of the identity running Terraform."
  }

  assert {
    condition     = azurerm_role_assignment.current_client_key_vault_admin[0].role_definition_name == "Key Vault Administrator"
    error_message = "The grant should be Key Vault Administrator."
  }

  assert {
    condition     = length(azurerm_role_assignment.key_vault_administrators) == 0
    error_message = "No listed grants should be created with the variable unset."
  }
}

run "listed_principals_replace_the_current_client" {
  command = plan

  variables {
    key_vault_administrator_principal_ids = [
      "00000000-0000-0000-0000-0000000000a1",
      "00000000-0000-0000-0000-0000000000a2",
    ]
  }

  assert {
    condition     = length(azurerm_role_assignment.key_vault_administrators) == 2
    error_message = "One grant should be created per listed ID."
  }

  assert {
    condition     = length(azurerm_role_assignment.current_client_key_vault_admin) == 0
    error_message = "The identity running Terraform should not be granted when IDs are listed."
  }

  assert {
    condition = toset([for a in azurerm_role_assignment.key_vault_administrators : a.principal_id]) == toset([
      "00000000-0000-0000-0000-0000000000a1",
      "00000000-0000-0000-0000-0000000000a2",
    ])
    error_message = "The grants should go to exactly the listed IDs."
  }

  assert {
    condition     = alltrue([for a in azurerm_role_assignment.key_vault_administrators : a.role_definition_name == "Key Vault Administrator"])
    error_message = "Every listed grant should be Key Vault Administrator."
  }
}

run "empty_set_grants_no_administrator" {
  command = plan

  variables {
    key_vault_administrator_principal_ids = []
  }

  assert {
    condition = alltrue([
      length(azurerm_role_assignment.current_client_key_vault_admin) == 0,
      length(azurerm_role_assignment.key_vault_administrators) == 0,
    ])
    error_message = "An empty set should create no Key Vault Administrator grant."
  }
}
