resource "azurerm_log_analytics_workspace" "log_analytics" {
  name                = var.log_analytics_workspace_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_key_vault" "key_vault" {
  count               = var.create_key_vault ? 1 : 0
  name                = var.key_vault_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  tags                = var.tags

  enable_rbac_authorization = true

  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = [var.subnet_id]
  }
}

data "azurerm_key_vault" "existing_key_vault" {
  count               = var.create_key_vault ? 0 : 1
  name                = var.key_vault_name
  resource_group_name = data.azurerm_resource_group.main.name
}

resource "azurerm_user_assigned_identity" "managed_identity" {
  count               = var.create_managed_identity ? 1 : 0
  name                = var.managed_identity_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = var.tags
}

data "azurerm_user_assigned_identity" "existing_managed_identity" {
  count               = var.create_managed_identity ? 0 : 1
  name                = var.managed_identity_name
  resource_group_name = data.azurerm_resource_group.main.name
}

resource "azurerm_role_assignment" "acr_pull" {
  count                = var.create_managed_identity ? 1 : 0
  scope                = data.azurerm_resource_group.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.managed_identity[0].principal_id
}

resource "azurerm_role_assignment" "storage_account_contributor" {
  count                = var.create_managed_identity ? 1 : 0
  scope                = data.azurerm_resource_group.main.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_user_assigned_identity.managed_identity[0].principal_id
}

resource "azurerm_role_assignment" "storage_blob_data_contributor" {
  count                = var.create_managed_identity ? 1 : 0
  scope                = data.azurerm_resource_group.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.managed_identity[0].principal_id
}

resource "azurerm_role_assignment" "storage_blob_data_reader" {
  count                = var.create_managed_identity ? 1 : 0
  scope                = data.azurerm_resource_group.main.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.managed_identity[0].principal_id
}

resource "azurerm_role_assignment" "key_vault_secrets_officer" {
  count                = var.create_managed_identity ? 1 : 0
  scope                = azurerm_key_vault.key_vault[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_user_assigned_identity.managed_identity[0].principal_id
}

resource "azurerm_container_app_environment" "container_app_env" {
  name                = "${var.resource_name}-env"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = var.tags

  infrastructure_subnet_id = var.subnet_id

  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics.id

  workload_profile {
    name                  = "minimumwp"
    minimum_count         = 0
    maximum_count         = 1
    workload_profile_type = "D4"
  }

  zone_redundancy_enabled = true
}

resource "azurerm_container_app" "container_app" {
  name                = "${var.resource_name}-app"
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = var.tags

  revision_mode                = "Single"
  container_app_environment_id = azurerm_container_app_environment.container_app_env.id

  identity {
    type = "UserAssigned"
    identity_ids = var.create_managed_identity ? [
      azurerm_user_assigned_identity.managed_identity[0].id
      ] : [
      data.azurerm_user_assigned_identity.existing_managed_identity[0].id
    ]
  }

  workload_profile_name = "minimumwp"

  secret {
    name  = "matillion-client-id"
    value = var.client_id
  }

  secret {
    name  = "matillion-client-secret"
    value = var.client_secret
  }

  template {
    min_replicas = 2
    max_replicas = 2

    container {
      name   = var.resource_name
      image  = var.container_image_url
      cpu    = "1.0"
      memory = "4Gi"

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
        value = var.create_key_vault ? azurerm_key_vault.key_vault[0].name : data.azurerm_key_vault.existing_key_vault[0].name
      }

      env {
        name  = "AZURE_CLIENT_ID"
        value = var.create_managed_identity ? azurerm_user_assigned_identity.managed_identity[0].client_id : data.azurerm_user_assigned_identity.existing_managed_identity[0].client_id
      }

      env {
        name        = "OAUTH_CLIENT_ID"
        secret_name = "matillion-client-id"
      }

      env {
        name        = "OAUTH_CLIENT_SECRET"
        secret_name = "matillion-client-secret"
      }

      // PROXY_HTTP
      // PROXY_HTTPS
      // PROXY_EXCLUDES
      // CUSTOM_CERT_LOCATION
      // EXTENSION_LIBRARY_LOCATION
      // EXTERNAL_DRIVER_LOCATION
      // AZURE_DEFAULT_SUBSCRIPTION_ID
    }
  }
}
