data "azurerm_client_config" "current" {}

locals {
  # Container Apps with workload profiles (Dedicated). Consumption profile won't
  # accept the 1:4 cpu:memory ratio used by `small`, so all sizes assume Dedicated.
  runner_size_map = {
    small  = { cpu = "1.0", memory = "4Gi", profile = "D4" }
    medium = { cpu = "2.0", memory = "8Gi", profile = "D4" }
    large  = { cpu = "4.0", memory = "16Gi", profile = "D4" }
    xlarge = { cpu = "8.0", memory = "32Gi", profile = "D8" }
  }

  # Intentionally mirrors runner_size_map — same T-shirt sizes, same Azure profile types.
  script_runner_size_map = {
    small  = { cpu = "1.0", memory = "4Gi", profile = "D4" }
    medium = { cpu = "2.0", memory = "8Gi", profile = "D4" }
    large  = { cpu = "4.0", memory = "16Gi", profile = "D4" }
    xlarge = { cpu = "8.0", memory = "32Gi", profile = "D8" }
  }

  container_cpu         = coalesce(var.container_cpu, local.runner_size_map[var.runner_size].cpu)
  container_memory      = coalesce(var.container_memory, local.runner_size_map[var.runner_size].memory)
  workload_profile_type = coalesce(
    var.workload_profile_type,
    (
      local.runner_size_map[var.runner_size].profile == "D8" ||
      (var.enable_script_runner && local.script_runner_size_map[var.script_runner_size].profile == "D8")
    ) ? "D8" : "D4"
  )

  script_runner_cpu    = local.script_runner_size_map[var.script_runner_size].cpu
  script_runner_memory = local.script_runner_size_map[var.script_runner_size].memory
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

# Role: AcrPull for managed identity. Scoped to the registry resource when
# container_acr_id is set (least privilege); falls back to subscription scope
# to preserve behaviour for deployments that pre-date this variable.
resource "azurerm_role_assignment" "acr_pull" {
  scope                = coalesce(var.container_acr_id, "/subscriptions/${data.azurerm_client_config.current.subscription_id}")
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

  # Authenticate image pulls with the managed identity when the image lives in a
  # private registry. Without this block the platform attempts an anonymous pull
  # (the AcrPull role alone is not enough) and a private registry returns 401.
  # Omitted for public images (container_acr_id = null) so they pull anonymously.
  dynamic "registry" {
    for_each = var.container_acr_id != null ? [1] : []
    content {
      server   = split("/", var.container_image_url)[0]
      identity = azurerm_user_assigned_identity.managed_identity.id
    }
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
        value = var.matillion_environment
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

  lifecycle {
    precondition {
      condition     = var.container_acr_id == null ? true : (
        lower(split(".", split("/", var.container_image_url)[0])[0]) ==
        lower(element(split("/", var.container_acr_id), length(split("/", var.container_acr_id)) - 1))
      )
      error_message = "container_acr_id registry name does not match the registry hostname in container_image_url — both must reference the same Azure Container Registry."
    }
  }
}

# Script Runner — opt-in via enable_script_runner

resource "azurerm_user_assigned_identity" "script_runner_identity" {
  count               = var.enable_script_runner ? 1 : 0
  name                = join("-", [var.name, "ca-runner-identity", lower(var.random_string_salt)])
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# AcrPull only when pulling from a private registry (script_runner_acr_id set),
# scoped to that registry. Public images pull anonymously and need no grant.
resource "azurerm_role_assignment" "script_runner_acr_pull" {
  count                = var.enable_script_runner && var.script_runner_acr_id != null ? 1 : 0
  scope                = var.script_runner_acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.script_runner_identity[0].principal_id
}

# Script runner reads blobs (inputs/artifacts) but never writes back — write-back
# goes through the agent identity. Reader rather than Contributor is intentional.
resource "azurerm_role_assignment" "script_runner_storage_blob_data_reader" {
  count                = var.enable_script_runner ? 1 : 0
  scope                = azurerm_storage_account.storage.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.script_runner_identity[0].principal_id
}

resource "azurerm_role_assignment" "script_runner_key_vault_secrets_user" {
  count                = var.enable_script_runner ? 1 : 0
  scope                = azurerm_key_vault.keyvault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.script_runner_identity[0].principal_id
}

resource "azurerm_container_app" "script_runner" {
  count = var.enable_script_runner ? 1 : 0

  name                         = join("-", [var.name, "script-runner", lower(var.random_string_salt)])
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.env.id
  revision_mode                = "Single"
  workload_profile_name        = "agentpool"
  tags                         = var.tags

  lifecycle {
    precondition {
      condition     = length(var.name) <= 11
      error_message = "name must be 11 characters or fewer when enable_script_runner = true (Azure Container App name limit is 32; the script runner suffix consumes 21 characters)."
    }
    precondition {
      condition     = trimspace(var.script_runner_authorized_keys) != ""
      error_message = "script_runner_authorized_keys must be set when enable_script_runner = true."
    }
    precondition {
      condition     = var.script_runner_acr_id == null ? true : (
        lower(split(".", split("/", var.script_runner_image_url)[0])[0]) ==
        lower(element(split("/", var.script_runner_acr_id), length(split("/", var.script_runner_acr_id)) - 1))
      )
      error_message = "script_runner_acr_id registry name does not match the registry hostname in script_runner_image_url — both must reference the same Azure Container Registry."
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.script_runner_identity[0].id]
  }

  # Authenticate image pulls with the runner identity when the image lives in a
  # private registry. Without this block the platform attempts an anonymous pull
  # (the AcrPull role alone is not enough) and a private registry returns 401.
  # Omitted for public images (script_runner_acr_id = null).
  dynamic "registry" {
    for_each = var.script_runner_acr_id != null ? [1] : []
    content {
      server   = split("/", var.script_runner_image_url)[0]
      identity = azurerm_user_assigned_identity.script_runner_identity[0].id
    }
  }

  secret {
    name  = "runner-authorized-keys"
    value = var.script_runner_authorized_keys
  }

  ingress {
    transport        = "tcp"
    external_enabled = false
    target_port      = 2222

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 1
    max_replicas = 1
    # 600s grace period gives in-flight SSH jobs time to complete after SIGTERM.
    # Effective only if the runner image propagates SIGTERM and waits for SSH
    # child processes to exit before the entrypoint returns.
    termination_grace_period_seconds = 600

    volume {
      name         = "runner-keys"
      storage_type = "Secret"
    }

    container {
      name   = "script-runner"
      image  = var.script_runner_image_url
      cpu    = local.script_runner_cpu
      memory = local.script_runner_memory

      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.script_runner_identity[0].client_id
      }

      env {
        name  = "RUNNER_AUTHORIZED_KEYS_FILE"
        value = "/run/secrets/runner-authorized-keys"
      }

      volume_mounts {
        name = "runner-keys"
        path = "/run/secrets"
      }
    }
  }
}
