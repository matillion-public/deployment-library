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

  # Set on the runner container when disable_script_execution is true. The
  # runner launches Python Script and Bash Script through these commands, so
  # pointing them at paths that do not exist makes both components fail at Run.
  # All three together are the tested set; do not drop one.
  script_execution_disabled_env = {
    SCRIPT_OOM_PROTECTION_ENABLED = "false"
    MTLN_PYTHON_3_COMMAND         = "/python-script-disabled-on-this-runner"
    MTLN_BASH_COMMAND             = "/bash-script-disabled-on-this-runner"
  }

  container_cpu    = coalesce(var.container_cpu, local.runner_size_map[var.runner_size].cpu)
  container_memory = coalesce(var.container_memory, local.runner_size_map[var.runner_size].memory)
  workload_profile_type = coalesce(
    var.workload_profile_type,
    (
      local.runner_size_map[var.runner_size].profile == "D8" ||
      (var.enable_script_runner && local.script_runner_size_map[var.script_runner_size].profile == "D8")
    ) ? "D8" : "D4"
  )

  script_runner_cpu    = local.script_runner_size_map[var.script_runner_size].cpu
  script_runner_memory = local.script_runner_size_map[var.script_runner_size].memory

  # Key Vault names are limited to 24 characters. The default is the base name,
  # "-kv-" and the salt, cut at 24, so a long base name loses salt characters.
  key_vault_name = lookup(var.resource_names, "key_vault", substr(join("-", [var.name, "kv", var.random_string_salt]), 0, 24))

  # The salt is unknown at plan on a new deployment, so the Key Vault name checks
  # read only var.name and assume the root's 6-character alphanumeric salt.
  key_vault_salt_length         = 6
  key_vault_name_without_salt   = substr("${var.name}-kv-", 0, 24)
  key_vault_name_keeps_salt     = length(var.name) + length("-kv-") + local.key_vault_salt_length <= 24
  key_vault_name_ends_in_hyphen = length(var.name) >= 24 - length("-kv-") && endswith(local.key_vault_name_without_salt, "-")
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "log_analytics" {
  name                = lookup(var.resource_names, "log_workspace", join("-", [var.name, "log-workspace", var.random_string_salt]))
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# Storage Account
resource "azurerm_storage_account" "storage" {
  name                = lookup(var.resource_names, "storage_account", substr(replace(join("", [var.name, "stca", var.random_string_salt]), "-", ""), 0, 24))
  resource_group_name = var.resource_group_name
  location            = var.location
  account_tier        = "Standard"
  # LRS keeps a single copy in one zone, which undercuts the zone redundancy the
  # Container App Environment claims via zone_redundancy_enabled. New
  # deployments should set ZRS; the default stays LRS so existing state does not
  # move underneath anyone. See runner/azure/container_apps/README.md for the
  # conversion path.
  account_replication_type        = var.storage_account_replication_type
  allow_nested_items_to_be_public = false
  tags                            = var.tags
}

# Key Vault
resource "azurerm_key_vault" "keyvault" {
  name                       = local.key_vault_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  rbac_authorization_enabled = true

  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    ip_rules                   = var.key_vault_allowed_ip_ranges
    virtual_network_subnet_ids = var.subnet_ids
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = contains(keys(var.resource_names), "key_vault") || !local.key_vault_name_ends_in_hyphen
      error_message = "The derived Key Vault name \"${local.key_vault_name_without_salt}\" ends in a hyphen, which Azure rejects. Shorten name to ${24 - length("-kv-") - local.key_vault_salt_length} characters or fewer so the name keeps the full salt, or set resource_names[\"key_vault\"]."
    }
  }
}

check "key_vault_name_keeps_full_salt" {
  assert {
    condition     = contains(keys(var.resource_names), "key_vault") || local.key_vault_name_keeps_salt
    error_message = "name is ${length(var.name)} characters, so the default Key Vault name keeps ${max(0, 24 - length(var.name) - length("-kv-"))} of the ${local.key_vault_salt_length} salt characters. Vault names are global and soft-deleted vaults keep their names for 7 days, so fewer salt characters make a collision more likely. On a new deployment, keep name at ${24 - length("-kv-") - local.key_vault_salt_length} characters or fewer, or set resource_names[\"key_vault\"]. On an existing deployment, do not change name: that replaces every default-named resource. See \"Key Vault Name\" in runner/azure/container_apps/README.md."
  }
}

# User Assigned Managed Identity
resource "azurerm_user_assigned_identity" "managed_identity" {
  name                = lookup(var.resource_names, "container_app_identity", join("-", [var.name, "ca-identity", var.random_string_salt]))
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Key Vault Administrator. With key_vault_administrator_principal_ids unset the
# identity running Terraform is the administrator, as before. When set, exactly
# the listed principals are administrators and the running identity is not granted.
resource "azurerm_role_assignment" "current_client_key_vault_admin" {
  count                = var.key_vault_administrator_principal_ids == null ? 1 : 0
  scope                = azurerm_key_vault.keyvault.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

moved {
  from = azurerm_role_assignment.current_client_key_vault_admin
  to   = azurerm_role_assignment.current_client_key_vault_admin[0]
}

resource "azurerm_role_assignment" "key_vault_administrators" {
  for_each             = var.key_vault_administrator_principal_ids == null ? toset([]) : var.key_vault_administrator_principal_ids
  scope                = azurerm_key_vault.keyvault.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = each.value

  # Azure rejects a second assignment with the same principal, role and scope.
  # This ordering destroys the current-client grant before a listed grant to the
  # same principal is created, and the reverse when the variable is unset.
  depends_on = [azurerm_role_assignment.current_client_key_vault_admin]
}

# AcrPull only when the runner image comes from a private registry
# (container_acr_id set), scoped to that registry. Public images pull
# anonymously (see the registry block on azurerm_container_app.app) and need
# no grant.
resource "azurerm_role_assignment" "acr_pull" {
  count                = var.container_acr_id != null ? 1 : 0
  scope                = var.container_acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.managed_identity.principal_id
}

moved {
  from = azurerm_role_assignment.acr_pull
  to   = azurerm_role_assignment.acr_pull[0]
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
  name                = lookup(var.resource_names, "container_app_environment", join("-", [var.name, "env", var.random_string_salt]))
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
  name                         = lookup(var.resource_names, "container_app", join("-", [var.name, "app", var.random_string_salt]))
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

      dynamic "env" {
        for_each = var.extension_library_location != "" ? [1] : []
        content {
          name  = "EXTENSION_LIBRARY_LOCATION"
          value = var.extension_library_location
        }
      }

      dynamic "env" {
        for_each = var.external_driver_location != "" ? [1] : []
        content {
          name  = "EXTERNAL_DRIVER_LOCATION"
          value = var.external_driver_location
        }
      }

      dynamic "env" {
        for_each = var.export_logs != "" ? [1] : []
        content {
          name  = "EXPORT_LOGS"
          value = var.export_logs
        }
      }

      dynamic "env" {
        for_each = var.proxy_protocol_http != "" ? [1] : []
        content {
          name  = "PROXY_PROTOCOL_HTTP"
          value = var.proxy_protocol_http
        }
      }

      dynamic "env" {
        for_each = var.proxy_protocol_https != "" ? [1] : []
        content {
          name  = "PROXY_PROTOCOL_HTTPS"
          value = var.proxy_protocol_https
        }
      }

      dynamic "env" {
        for_each = var.disable_script_execution ? local.script_execution_disabled_env : {}
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition = var.container_acr_id == null ? true : (
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
  name                = lookup(var.resource_names, "script_runner_identity", join("-", [var.name, "ca-runner-identity", var.random_string_salt]))
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
# goes through the runner identity. Reader rather than Contributor is intentional.
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

  name                         = lookup(var.resource_names, "script_runner_app", join("-", [var.name, "script-runner", var.random_string_salt]))
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
      condition = var.script_runner_acr_id == null ? true : (
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

      dynamic "env" {
        for_each = var.extension_library_location != "" ? [1] : []
        content {
          name  = "EXTENSION_LIBRARY_LOCATION"
          value = var.extension_library_location
        }
      }

      volume_mounts {
        name = "runner-keys"
        path = "/run/secrets"
      }
    }
  }
}
