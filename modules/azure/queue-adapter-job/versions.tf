terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # 1.2+ for the lifecycle precondition in main.tf; siblings only need 1.0.
  required_version = ">= 1.2"
}
