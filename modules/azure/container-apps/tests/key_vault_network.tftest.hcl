# Run with: terraform test  (from modules/azure/container-apps)
#
# key_vault_allowed_ip_ranges adds public IPv4 addresses or CIDRs to the Key
# Vault firewall so an operator can add secrets from outside the VNet. Empty by
# default, so the vault stays closed to everything outside subnet_ids unless the
# caller opts in. Uses a mock provider, so no Azure credentials are needed.

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

run "key_vault_denies_by_default_with_no_ip_rules" {
  command = plan

  assert {
    condition     = length(azurerm_key_vault.keyvault.network_acls[0].ip_rules) == 0
    error_message = "With key_vault_allowed_ip_ranges unset the vault must have no IP rules."
  }

  assert {
    condition     = azurerm_key_vault.keyvault.network_acls[0].default_action == "Deny"
    error_message = "The Key Vault firewall must deny by default."
  }

  assert {
    condition     = azurerm_key_vault.keyvault.network_acls[0].bypass == "AzureServices"
    error_message = "The Key Vault firewall must let Azure trusted services through."
  }

  assert {
    condition     = toset(azurerm_key_vault.keyvault.network_acls[0].virtual_network_subnet_ids) == toset(var.subnet_ids)
    error_message = "The Key Vault firewall must allow exactly the subnets in subnet_ids."
  }
}

run "allowed_ip_ranges_become_ip_rules" {
  command = plan

  variables {
    key_vault_allowed_ip_ranges = ["203.0.113.0/24", "198.51.100.7"]
  }

  assert {
    condition     = toset(azurerm_key_vault.keyvault.network_acls[0].ip_rules) == toset(["203.0.113.0/24", "198.51.100.7"])
    error_message = "Every entry in key_vault_allowed_ip_ranges must become a Key Vault IP rule."
  }

  assert {
    condition     = azurerm_key_vault.keyvault.network_acls[0].default_action == "Deny"
    error_message = "Adding IP rules must leave the Key Vault firewall denying by default."
  }

  assert {
    condition     = toset(azurerm_key_vault.keyvault.network_acls[0].virtual_network_subnet_ids) == toset(var.subnet_ids)
    error_message = "Adding IP rules must leave the subnet rules unchanged."
  }
}

run "invalid_ip_range_is_rejected" {
  command = plan

  variables {
    key_vault_allowed_ip_ranges = ["203.0.113.10/24"]
  }

  expect_failures = [var.key_vault_allowed_ip_ranges]
}

run "ipv6_range_is_rejected" {
  command = plan

  variables {
    key_vault_allowed_ip_ranges = ["2001:db8::/32"]
  }

  expect_failures = [var.key_vault_allowed_ip_ranges]
}

run "whole_internet_range_is_rejected" {
  command = plan

  variables {
    key_vault_allowed_ip_ranges = ["0.0.0.0/0"]
  }

  expect_failures = [var.key_vault_allowed_ip_ranges]
}

run "prefix_shorter_than_8_is_rejected" {
  command = plan

  variables {
    key_vault_allowed_ip_ranges = ["64.0.0.0/7"]
  }

  expect_failures = [var.key_vault_allowed_ip_ranges]
}

run "slash_32_is_rejected" {
  command = plan

  variables {
    key_vault_allowed_ip_ranges = ["203.0.113.10/32"]
  }

  expect_failures = [var.key_vault_allowed_ip_ranges]
}

run "slash_31_is_rejected" {
  command = plan

  variables {
    key_vault_allowed_ip_ranges = ["203.0.113.10/31"]
  }

  expect_failures = [var.key_vault_allowed_ip_ranges]
}

run "private_range_is_rejected" {
  command = plan

  variables {
    key_vault_allowed_ip_ranges = ["10.0.2.0/24"]
  }

  expect_failures = [var.key_vault_allowed_ip_ranges]
}

run "private_address_is_rejected" {
  command = plan

  variables {
    key_vault_allowed_ip_ranges = ["192.168.1.5"]
  }

  expect_failures = [var.key_vault_allowed_ip_ranges]
}

run "range_containing_a_private_range_is_rejected" {
  command = plan

  variables {
    key_vault_allowed_ip_ranges = ["172.0.0.0/8"]
  }

  expect_failures = [var.key_vault_allowed_ip_ranges]
}

run "public_ranges_next_to_private_ranges_are_accepted" {
  command = plan

  variables {
    key_vault_allowed_ip_ranges = ["11.0.0.0/8", "172.32.0.0/11", "172.15.255.255", "192.169.0.0/16"]
  }

  assert {
    condition     = length(azurerm_key_vault.keyvault.network_acls[0].ip_rules) == 4
    error_message = "Public ranges adjacent to RFC 1918 ranges must be accepted."
  }
}
