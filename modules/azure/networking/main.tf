locals {
  # ["*"] maps to source_address_prefix, the form earlier versions wrote, so
  # deployments that keep the default see no diff.
  https_from_any_source = length(var.https_inbound_source_prefixes) == 1 && contains(var.https_inbound_source_prefixes, "*")
}

resource "azurerm_virtual_network" "vnet" {
  name                = lookup(var.resource_names, "vnet", join("-", [var.name, "vnet", var.random_string_salt]))
  address_space       = [var.vnet_address_space]
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet" "subnets" {
  count = length(var.subnet_configs)
  name = coalesce(
    var.subnet_configs[count.index].name,
    join("-", [var.name, "subnet", var.random_string_salt, count.index])
  )
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [cidrsubnet(var.vnet_address_space, var.subnet_configs[count.index].newbits, var.subnet_configs[count.index].netnum)]

  service_endpoints = var.service_endpoints

  dynamic "delegation" {
    for_each = var.subnet_configs[count.index].delegation != null ? [var.subnet_configs[count.index].delegation] : []
    content {
      name = delegation.value.name
      service_delegation {
        name    = delegation.value.service_delegation.name
        actions = delegation.value.service_delegation.actions
      }
    }
  }
}

resource "azurerm_network_security_group" "nsg" {
  name                = lookup(var.resource_names, "nsg", join("-", [var.name, "runner-nsg", var.random_string_salt]))
  location            = var.location
  resource_group_name = var.resource_group_name

  # Attribute syntax, not a dynamic block: security_rule is Optional+Computed, so
  # zero dynamic blocks would keep the rule from state instead of removing it.
  security_rule = [
    for prefixes in(length(var.https_inbound_source_prefixes) > 0 ? [var.https_inbound_source_prefixes] : []) : {
      name                                       = "AllowHTTPS"
      description                                = null
      priority                                   = 100
      direction                                  = "Inbound"
      access                                     = "Allow"
      protocol                                   = "Tcp"
      source_port_range                          = "*"
      source_port_ranges                         = null
      destination_port_range                     = "443"
      destination_port_ranges                    = null
      source_address_prefix                      = local.https_from_any_source ? "*" : null
      source_address_prefixes                    = local.https_from_any_source ? null : prefixes
      source_application_security_group_ids      = null
      destination_address_prefix                 = "*"
      destination_address_prefixes               = null
      destination_application_security_group_ids = null
    }
  ]

  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg" {
  for_each = {
    for idx, subnet in azurerm_subnet.subnets : idx => subnet
  }

  subnet_id                 = each.value.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# --- NAT Gateway for controlled outbound egress ---

resource "azurerm_public_ip" "nat_gateway_ip" {
  count               = var.enable_nat_gateway ? 1 : 0
  name                = lookup(var.resource_names, "nat_public_ip", join("-", [var.name, "nat-pip", var.random_string_salt]))
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}

resource "azurerm_nat_gateway" "main" {
  count                   = var.enable_nat_gateway ? 1 : 0
  name                    = lookup(var.resource_names, "nat_gateway", join("-", [var.name, "nat-gw", var.random_string_salt]))
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = var.nat_gateway_idle_timeout

  tags = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  count                = var.enable_nat_gateway ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.main[0].id
  public_ip_address_id = azurerm_public_ip.nat_gateway_ip[0].id
}

resource "azurerm_subnet_nat_gateway_association" "subnets" {
  for_each = var.enable_nat_gateway ? {
    for idx, subnet in azurerm_subnet.subnets : idx => subnet
  } : {}

  subnet_id      = each.value.id
  nat_gateway_id = azurerm_nat_gateway.main[0].id
}
