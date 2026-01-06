# Azure Blob Storage Backend Configuration for AKS Deployment
terraform {
  # Uncomment the backend block below to use Azure Blob Storage for remote state
  # backend "azurerm" {
  #   resource_group_name  = "your-terraform-state-rg"
  #   storage_account_name = "yourterraformstatesa"
  #   container_name       = "terraform-states"
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