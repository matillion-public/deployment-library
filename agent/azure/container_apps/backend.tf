# Azure Blob Storage Backend Configuration for Container Apps Deployment
terraform {
  backend "azurerm" {
    # Storage account will be dynamically configured during deployment
    # resource_group_name  = "${resource_group_name}"
    # storage_account_name = "${storage_account_name}"
    # container_name       = "terraform-states"
    # key                  = "container_apps/${region}/${cluster_name}/terraform.tfstate"
  }
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  
  required_version = ">= 1.0"
}