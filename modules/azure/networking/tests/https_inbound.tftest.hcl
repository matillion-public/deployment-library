# Run with: terraform test  (from modules/azure/networking)
#
# Sources of the AllowHTTPS inbound rule on the subnet NSG. Uses mock
# providers, so no Azure credentials or resources are needed.

mock_provider "azurerm" {
  mock_resource "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/s"
    }
  }

  mock_resource "azurerm_network_security_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.Network/networkSecurityGroups/nsg"
    }
  }
}

variables {
  name                = "t"
  random_string_salt  = "abc123"
  location            = "uksouth"
  resource_group_name = "rg"
  tags                = {}
}

run "default_allows_https_from_any_source" {
  command = plan

  assert {
    condition     = length(azurerm_network_security_group.nsg.security_rule) == 1
    error_message = "The default must create exactly one rule."
  }

  assert {
    condition     = one(azurerm_network_security_group.nsg.security_rule).name == "AllowHTTPS"
    error_message = "The rule must be named AllowHTTPS."
  }

  assert {
    condition     = one(azurerm_network_security_group.nsg.security_rule).priority == 100
    error_message = "The rule must keep priority 100."
  }

  assert {
    condition     = one(azurerm_network_security_group.nsg.security_rule).destination_port_range == "443"
    error_message = "The rule must allow destination port 443."
  }

  assert {
    condition     = one(azurerm_network_security_group.nsg.security_rule).source_address_prefix == "*"
    error_message = "[\"*\"] must set source_address_prefix to \"*\"."
  }
}

run "empty_list_has_no_rule" {
  command = plan

  variables {
    https_inbound_source_prefixes = []
  }

  assert {
    condition     = length(azurerm_network_security_group.nsg.security_rule) == 0
    error_message = "An empty list must create no rule."
  }
}

run "cidr_list_sets_source_prefixes" {
  command = plan

  variables {
    https_inbound_source_prefixes = ["203.0.113.0/24", "198.51.100.0/24"]
  }

  assert {
    condition     = one(azurerm_network_security_group.nsg.security_rule).source_address_prefixes == toset(["203.0.113.0/24", "198.51.100.0/24"])
    error_message = "A CIDR list must set source_address_prefixes to the listed ranges."
  }
}

run "star_with_other_prefixes_is_rejected" {
  command = plan

  variables {
    https_inbound_source_prefixes = ["*", "10.0.0.0/8"]
  }

  expect_failures = [var.https_inbound_source_prefixes]
}

run "rule_applied_with_any_source" {
  variables {
    https_inbound_source_prefixes = ["*"]
  }

  assert {
    condition     = length(azurerm_network_security_group.nsg.security_rule) == 1
    error_message = "The applied NSG must hold the rule."
  }
}

# Reads the state of the previous run: removing the rule from an NSG that has it.
run "empty_list_removes_applied_rule" {
  command = plan

  variables {
    https_inbound_source_prefixes = []
  }

  assert {
    condition     = length(azurerm_network_security_group.nsg.security_rule) == 0
    error_message = "An empty list must remove a rule already in state."
  }
}
