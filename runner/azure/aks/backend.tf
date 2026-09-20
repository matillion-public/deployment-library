# Azure Blob Storage Backend Configuration for AKS Deployment
terraform {
  # Uncomment the backend block below to use Azure Blob Storage for remote state.
  # All three names come from modules/azure/state-management — take them from its
  # backend_config output rather than typing them, since resource_names can change
  # any of the three and a mismatch here fails terraform init.
  # backend "azurerm" {
  #   resource_group_name  = "<state_management.backend_config.resource_group_name>"
  #   storage_account_name = "<state_management.backend_config.storage_account_name>"
  #   container_name       = "<state_management.backend_config.container_name>"
  #   key                  = "aks/terraform.tfstate"
  # }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }

  required_version = ">= 1.0"
}