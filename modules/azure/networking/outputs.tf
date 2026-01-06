output "vnet_name" {
  value = azurerm_virtual_network.aks_vnet.name
}

output "vnet_id" {
  value = azurerm_virtual_network.aks_vnet.id
}

output "subnet_ids" {
  value = azurerm_subnet.aks_subnets[*].id
}