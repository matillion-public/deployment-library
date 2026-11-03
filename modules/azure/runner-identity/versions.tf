terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # 1.2+ for the lifecycle precondition and postcondition in main.tf.
  required_version = ">= 1.2"
}
