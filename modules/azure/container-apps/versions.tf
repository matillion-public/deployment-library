terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # 1.5+ for the check block, 1.3+ for endswith, 1.2+ for the lifecycle precondition in main.tf.
  required_version = ">= 1.5"
}
