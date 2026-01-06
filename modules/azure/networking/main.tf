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