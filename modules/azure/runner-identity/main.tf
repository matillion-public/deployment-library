# Per-runner Azure identity: one User Assigned Managed Identity per runner
# deployment, federated to that runner's Kubernetes service account. Key Vault
# access is read only, one secret at a time or vault-wide, or read and write
# across a vault the runner has to itself, or none at all.
#
# This exists so several business units can share one cluster and one Key Vault
# without sharing credentials. The shared-identity arrangement in
# modules/azure/aks grants "Key Vault Secrets User" at the vault scope, which
# means every runner using it can read every secret in the vault — fine for a
# single-tenant deployment, not acceptable once the vault holds another
# business unit's credentials.

# Every count and for_each below is driven by flags known at plan, never by the vault
# name: a caller that creates the vault in the same apply can't know its name yet.
data "azurerm_key_vault" "target" {
  count = var.grant_key_vault_access ? 1 : 0

  name                = var.key_vault_name
  resource_group_name = var.key_vault_resource_group_name

  lifecycle {
    postcondition {
      # Per-secret scoping is only expressible under the Azure RBAC permission
      # model. Legacy vault access policies cannot scope below the vault, so on
      # such a vault the role assignments below are accepted by Azure and then
      # do nothing — the runner keeps whatever the access policies gave it.
      # Failing here is the difference between an error and a silent
      # authorisation hole.
      condition     = self.rbac_authorization_enabled
      error_message = "Key Vault '${self.name}' uses the legacy access-policy permission model. Per-secret scoping requires Azure RBAC authorization (enable_rbac_authorization = true). Access policies cannot scope below the vault, so this module would appear to apply cleanly while granting nothing. Use an RBAC-enabled vault, or migrate this one by granting the equivalent RBAC roles first and flipping the model afterwards."
    }
  }
}

resource "azurerm_user_assigned_identity" "runner" {
  name                = lookup(var.resource_names, "tenant_runner_identity", join("-", [var.name, "runner-identity"]))
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  lifecycle {
    precondition {
      # Without an account the storage grant is skipped, so a container name on
      # its own would quietly grant nothing.
      condition     = var.storage_container_name == "" || var.storage_account_id != ""
      error_message = "storage_container_name is set but storage_account_id is empty. The container scope is built from the account ID, so without it no storage access is granted at all."
    }

    precondition {
      condition     = var.grant_key_vault_access || (length(var.key_vault_secret_names) == 0 && !var.grant_vault_wide_secret_access && !var.grant_vault_wide_secret_write)
      error_message = "key_vault_secret_names, grant_vault_wide_secret_access and grant_vault_wide_secret_write each need grant_key_vault_access. Without it the identity gets no Key Vault access."
    }

    precondition {
      condition     = !contains([for id in var.storage_account_ids : lower(id)], lower(var.storage_account_id))
      error_message = "storage_account_id is also in storage_account_ids. Give each storage account once: an existing caller keeps it in storage_account_id, since moving it re-creates its role assignment."
    }
  }
}

# Binds the identity to exactly one Kubernetes service account in one namespace.
# The subject is the whole of the trust relationship — a runner deployed with a
# different serviceAccount.name or into a different namespace simply fails to
# get a token, rather than falling back to someone else's identity.
resource "azurerm_federated_identity_credential" "runner" {
  name                = lookup(var.resource_names, "tenant_runner_federated_credential", join("-", [var.name, "runner-fic"]))
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.runner.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  subject             = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
}

# The script runner is a separate pod with a separate service account, but the
# same blast radius as the runner that drives it, so it shares the identity.
resource "azurerm_federated_identity_credential" "script_runner" {
  count               = var.script_runner_service_account_name != "" ? 1 : 0
  name                = lookup(var.resource_names, "tenant_script_runner_federated_credential", join("-", [var.name, "script-runner-fic"]))
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.runner.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  subject             = "system:serviceaccount:${var.namespace}:${var.script_runner_service_account_name}"
}

# One role assignment per secret, scoped to the individual secret rather than
# the vault. This is the whole point of the module.
resource "azurerm_role_assignment" "secret" {
  for_each = var.grant_key_vault_access ? toset(var.key_vault_secret_names) : toset([])

  scope                = "${data.azurerm_key_vault.target[0].id}/secrets/${each.value}"
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.runner.principal_id
}

# Vault-scoped access, for a vault that belongs to one tenant. There the vault
# boundary is the tenant boundary and per-secret assignments add maintenance
# without adding safety. On a shared vault this hands over every other tenant's
# secrets, which is why it is opt-in rather than the default.
resource "azurerm_role_assignment" "vault_wide_secrets_user" {
  count = var.grant_key_vault_access && var.grant_vault_wide_secret_access ? 1 : 0

  scope                = data.azurerm_key_vault.target[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.runner.principal_id
}

# Read, create, update and list across the vault: the calls a runner makes to save
# a secret created in Matillion (getSecret, then setSecret) and to list secrets
# (listPropertiesOfSecrets). No built-in role grants setSecret without also
# granting delete, purge, backup and restore, so this is Key Vault Secrets Officer.
# Only for a vault the runner has to itself: on a shared vault it could overwrite
# or delete every other tenant's secrets.
resource "azurerm_role_assignment" "vault_wide_secrets_officer" {
  count = var.grant_key_vault_access && var.grant_vault_wide_secret_write ? 1 : 0

  scope                = data.azurerm_key_vault.target[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_user_assigned_identity.runner.principal_id
}

# Reader on the vault covers metadata only — no secret values. The runner needs
# it to resolve the vault before reading anything from it. Note this does expose
# the *names* of every secret in the vault, including other tenants'.
resource "azurerm_role_assignment" "vault_reader" {
  count = var.grant_key_vault_access && var.grant_vault_reader ? 1 : 0

  scope                = data.azurerm_key_vault.target[0].id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.runner.principal_id
}

# Account scope reaches every container in the account, so tenants sharing one
# account read and write each other's blobs. A container scope keeps each
# tenant to its own container, the same way the secret grants above keep each
# tenant to its own secrets.
resource "azurerm_role_assignment" "storage" {
  count = var.storage_account_id != "" ? 1 : 0

  scope                = var.storage_container_name == "" ? var.storage_account_id : "${var.storage_account_id}/blobServices/default/containers/${var.storage_container_name}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.runner.principal_id

  # Moving between account and container scope replaces the assignment. Creating
  # the new one first keeps the runner's staging access unbroken in between.
  lifecycle {
    create_before_destroy = true
  }
}

# A separate resource, so the single-account grant above keeps its address and an
# upgrade never removes and re-creates it.
resource "azurerm_role_assignment" "storage_accounts" {
  for_each = toset(var.storage_account_ids)

  scope                = each.value
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.runner.principal_id
}

# Blob data roles carry no Azure Resource Manager access, and the runner needs two
# things from it on each account: to find the account (the storage account picker
# lists accounts through Resource Manager), and its keys, from which it signs the
# SAS a Snowflake or Databricks load from Azure staging is given. Reader and Data
# Access is the built-in role with read and listKeys and nothing more. Keys are
# broader than the blob role, covering the account's queues, tables and files too,
# and last until rotated, which is why this is opt-in.
resource "azurerm_role_assignment" "storage_keys" {
  for_each = var.grant_storage_account_keys ? toset(var.storage_account_ids) : toset([])

  scope                = each.value
  role_definition_name = "Reader and Data Access"
  principal_id         = azurerm_user_assigned_identity.runner.principal_id
}
