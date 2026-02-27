output "vnet_name" {
  value = azurerm_virtual_network.aks_vnet.name
}

output "vnet_id" {
  value = azurerm_virtual_network.aks_vnet.id
}

output "subnet_ids" {
  value      = azurerm_subnet.aks_subnets[*].id
  depends_on = [azurerm_subnet_nat_gateway_association.aks_subnets]
}

output "nat_gateway_id" {
  value = var.enable_nat_gateway ? azurerm_nat_gateway.main[0].id : null
}

output "nat_gateway_public_ip" {
  value = var.enable_nat_gateway ? azurerm_public_ip.nat_gateway_ip[0].ip_address : null
}