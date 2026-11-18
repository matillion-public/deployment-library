# Azure Provider Configuration for an existing AKS cluster
provider "azurerm" {
  features {
    key_vault {
      # The vault has purge protection, so Azure refuses a purge until the retention
      # period ends. Don't try: a destroyed runner's vault stays recoverable.
      purge_soft_delete_on_destroy = false
    }
  }
  subscription_id = var.azure_subscription_id
}
