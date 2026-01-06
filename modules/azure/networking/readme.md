# Terraform Configuration for Azure Resources

This Terraform configuration sets up various Azure resources including a Resource Group, Virtual Network, and Subnets.

## Input Variables

Defines the input variables used in the Terraform configurations:

- `use_existing_subnet`: Boolean to determine if an existing subnet should be used.
- `existing_subnet_name`: Name of the existing subnet.
- `name`: Name prefix for resources.
- `use_existing_resource_group`: Boolean to determine if an existing resource group should be used.
- `existing_resource_group_name`: Name of the existing resource group.
- `resource_group_name`: Name of the resource group.
- `use_existing_vnet`: Boolean to determine if an existing virtual network should be used.
- `existing_vnet_name`: Name of the existing virtual network.
- `existing_gw_vnet_name`: Name of the existing gateway virtual network.
- `location`: Azure region for resources.

## Outputs

Defines the outputs of the Terraform configurations:

- `vnet_name`: The name of the virtual network.
- `vnet_id`: The ID of the virtual network.
- `subnet_id`: The ID of the AKS subnet.
- `gw_subnet_id`: The ID of the application gateway subnet.
- `address_prefixes`: The address prefixes of the AKS subnet.

## Resources

### azurerm_virtual_network

Creates a Virtual Network with the following configurations:

- **Name**: "aks-vnet"
- **Address Space**: ["10.0.0.0/16"]
- **Location**: Specified by `location`
- **Resource Group**: Determined by `use_existing_resource_group` and either `existing_resource_group_name` or `resource_group_name`

### azurerm_subnet (aks_subnet)

Creates a Subnet for AKS with the following configurations:

- **Name**: Determined by `use_existing_subnet` and either `existing_subnet_name` or a combination of `name` and "subnet"
- **Resource Group**: Determined by `use_existing_resource_group` and either `existing_resource_group_name` or `resource_group_name`
- **Virtual Network Name**: Determined by `use_existing_vnet` and either `existing_vnet_name` or the name of the created virtual network
- **Address Prefixes**: ["10.0.1.0/24"]
- **Service Endpoints**: ["Microsoft.Storage", "Microsoft.KeyVault"]

### azurerm_subnet (appgw_subnet)

Creates a Subnet for Application Gateway with the following configurations:

- **Name**: Determined by `use_existing_subnet` and either `existing_subnet_name` or a combination of `name`, "appgw", and "subnet"
- **Resource Group**: Determined by `use_existing_resource_group` and either `existing_resource_group_name` or `resource_group_name`
- **Virtual Network Name**: Determined by `use_existing_subnet` and either `existing_gw_vnet_name` or the name of the created virtual network
- **Address Prefixes**: ["10.0.2.0/24"]