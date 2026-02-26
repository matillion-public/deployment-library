resource "azurerm_virtual_network" "aks_vnet" {
  name                = join("-", [var.name, "vnet", var.random_string_salt])
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_subnet" "aks_subnets" {
  count = 2
  name                 = join("-", [var.name, "subnet", var.random_string_salt, count.index])
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.aks_vnet.name
  address_prefixes     = ["10.0.${count.index + 1}.0/24"]

  service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
}

resource "azurerm_network_security_group" "aks_security_group" {
  name                = join("-", [var.name, "agent-nsg", var.random_string_salt])
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg" {
  for_each = {
    for idx, subnet in azurerm_subnet.aks_subnets : idx => subnet
  }

  subnet_id                 = each.value.id
  network_security_group_id = azurerm_network_security_group.aks_security_group.id
}

# --- NAT Gateway for controlled outbound egress ---

resource "azurerm_public_ip" "nat_gateway_ip" {
  count               = var.enable_nat_gateway ? 1 : 0
  name                = join("-", [var.name, "nat-pip", var.random_string_salt])
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}

resource "azurerm_nat_gateway" "main" {
  count                   = var.enable_nat_gateway ? 1 : 0
  name                    = join("-", [var.name, "nat-gw", var.random_string_salt])
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

resource "azurerm_subnet_nat_gateway_association" "aks_subnets" {
  for_each = var.enable_nat_gateway ? {
    for idx, subnet in azurerm_subnet.aks_subnets : idx => subnet
  } : {}

  subnet_id      = each.value.id
  nat_gateway_id = azurerm_nat_gateway.main[0].id
}