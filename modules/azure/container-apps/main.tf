data "azurerm_client_config" "current" {}

locals {
  # Container Apps with workload profiles (Dedicated). Consumption profile won't
  # accept the 1:4 cpu:memory ratio used by `small`, so all sizes assume Dedicated.
  agent_size_map = {
    small  = { cpu = "1.0", memory = "4Gi", profile = "D4" }
    medium = { cpu = "2.0", memory = "8Gi", profile = "D4" }
    large  = { cpu = "4.0", memory = "16Gi", profile = "D4" }
    xlarge = { cpu = "8.0", memory = "32Gi", profile = "D8" }
  }

  container_cpu         = coalesce(var.container_cpu, local.agent_size_map[var.agent_size].cpu)
  container_memory      = coalesce(var.container_memory, local.agent_size_map[var.agent_size].memory)
  workload_profile_type = coalesce(var.workload_profile_type, local.agent_size_map[var.agent_size].profile)
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "log_analytics" {
  name                = join("-", [var.name, "log-workspace", var.random_string_salt])
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# Storage Account
resource "azurerm_storage_account" "storage" {
  name                            = substr(lower(join("", [var.name, "stca", var.random_string_salt])), 0, 24)
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = false
  tags                            = var.tags
}

# Key Vault
resource "azurerm_key_vault" "keyvault" {
  name                       = substr(join("-", [var.name, "kv", var.random_string_salt]), 0, 24)
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  rbac_authorization_enabled = true

  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = var.subnet_ids
  }

  tags = var.tags
}

# User Assigned Managed Identity
resource "azurerm_user_assigned_identity" "managed_identity" {
  name                = join("-", [var.name, "ca-identity", var.random_string_salt])
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Role: Key Vault Administrator for current deployer
resource "azurerm_role_assignment" "current_client_key_vault_admin" {
  scope                = azurerm_key_vault.keyvault.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Role: AcrPull for managed identity
resource "azurerm_role_assignment" "acr_pull" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.managed_identity.principal_id
}

# Role: Storage Account Contributor
resource "azurerm_role_assignment" "storage_account_contributor" {
  scope                = azurerm_storage_account.storage.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_user_assigned_identity.managed_identity.principal_id
}

# Role: Storage Blob Data Contributor
resource "azurerm_role_assignment" "storage_blob_data_contributor" {
  scope                = azurerm_storage_account.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.managed_identity.principal_id
}

# Role: Key Vault Secrets Officer
resource "azurerm_role_assignment" "key_vault_secrets_officer" {
  scope                = azurerm_key_vault.keyvault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_user_assigned_identity.managed_identity.principal_id
}

# Role: Key Vault Secrets User
resource "azurerm_role_assignment" "key_vault_secrets_user" {
  scope                = azurerm_key_vault.keyvault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.managed_identity.principal_id
}

# Role: Reader on Key Vault for metadata access
resource "azurerm_role_assignment" "key_vault_reader" {
  scope                = azurerm_key_vault.keyvault.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.managed_identity.principal_id
}

# Container App Environment
resource "azurerm_container_app_environment" "env" {
  name                = join("-", [var.name, "env", var.random_string_salt])
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  infrastructure_subnet_id   = var.subnet_ids[0]
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics.id
  zone_redundancy_enabled    = var.zone_redundancy_enabled

  workload_profile {
    name                  = "agentpool"
    minimum_count         = 0
    maximum_count         = var.workload_profile_max_count
    workload_profile_type = local.workload_profile_type
  }
}

# Container App
resource "azurerm_container_app" "app" {
  name                         = join("-", [var.name, "app", var.random_string_salt])
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.env.id
  revision_mode                = "Single"
  workload_profile_name        = "agentpool"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.managed_identity.id]
  }

  secret {
    name  = "matillion-client-id"
    value = var.client_id
  }

  secret {
    name  = "matillion-client-secret"
    value = var.client_secret
  }

  template {
    min_replicas = var.replica_count
    max_replicas = var.replica_count

    container {
      name   = var.name
      image  = var.container_image_url
      cpu    = local.container_cpu
      memory = local.container_memory

      env {
        name  = "CLOUD_PROVIDER"
        value = "AZURE"
      }

      env {
        name  = "ACCOUNT_ID"
        value = var.account_id
      }

      env {
        name  = "AGENT_ID"
        value = var.agent_id
      }

      env {
        name  = "MATILLION_REGION"
        value = var.matillion_cloud_region
      }

      env {
        name  = "MATILLION_ENV"
        value = ""
      }

      env {
        name  = "DEFAULT_KEYVAULT"
        value = azurerm_key_vault.keyvault.name
      }

      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.managed_identity.client_id
      }

      env {
        name        = "OAUTH_CLIENT_ID"
        secret_name = "matillion-client-id"
      }

      env {
        name        = "OAUTH_CLIENT_SECRET"
        secret_name = "matillion-client-secret"
      }
    }
  }
}
