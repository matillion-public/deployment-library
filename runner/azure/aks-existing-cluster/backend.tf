# Azure Blob Storage Backend Configuration for an existing AKS cluster
terraform {
  # Uncomment and fill in to use Azure Blob Storage for remote state. Take the three
  # names from modules/azure/state-management's backend_config output rather than
  # typing them: resource_names can change any of them, and a mismatch here fails
  # terraform init.
  # backend "azurerm" {
  #   resource_group_name  = "<state_management.backend_config.resource_group_name>"
  #   storage_account_name = "<state_management.backend_config.storage_account_name>"
  #   container_name       = "<state_management.backend_config.container_name>"
  #   key                  = "aks/<cluster_name>/<name>/terraform.tfstate"
  # }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.42"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  required_version = ">= 1.2"
}
