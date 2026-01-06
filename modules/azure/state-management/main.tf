# Azure Storage Backend State Management Module
# Creates Storage Account and Container for Terraform state management

locals {
  storage_account_name = "${replace(var.account_id, "-", "")}tfstates"
  # Storage account names must be lowercase and alphanumeric only
  storage_account_name_clean = substr(replace(lower(local.storage_account_name), "/[^a-z0-9]/", ""), 0, 24)
}

# Resource group for state management resources
resource "azurerm_resource_group" "state_management" {
  name     = "${var.resource_group_prefix}-terraform-state"
  location = var.location

  tags = merge(var.tags, {
    Purpose   = "TerraformState"
    ManagedBy = "Terraform"
  })
}

# Storage account for Terraform state
resource "azurerm_storage_account" "terraform_state" {
  name                     = local.storage_account_name_clean
  resource_group_name      = azurerm_resource_group.state_management.name
  location                 = azurerm_resource_group.state_management.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  # Enable versioning and encryption
  blob_properties {
    versioning_enabled = true
  }

  tags = merge(var.tags, {
    Name      = "Terraform State Storage"
    Purpose   = "TerraformState"
    ManagedBy = "Terraform"
  })
}

# Storage container for state files
resource "azurerm_storage_container" "terraform_state" {
  name                  = "terraform-states"
  storage_account_name  = azurerm_storage_account.terraform_state.name
  container_access_type = "private"
}

# Role assignment to allow deployment principal access to storage
resource "azurerm_role_assignment" "storage_blob_data_contributor" {
  count                = length(var.principal_ids)
  scope                = azurerm_storage_account.terraform_state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.principal_ids[count.index]
}