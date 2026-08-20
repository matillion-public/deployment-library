# modules/core/auth-msi  (Azure)
#
# FOUNDATION resource: the agent managed identity ("agent_role") =
# azurerm_user_assigned_identity. The Azure compute module runs the agent as this
# identity. Optionally stores the app client_secret in Key Vault and grants the
# identity Key Vault Secrets User.

locals {
  identity_name = "${var.deployment_name}-agent-id"
  use_kv        = var.key_vault_id != ""
}

resource "azurerm_user_assigned_identity" "agent_role" {
  name                = local.identity_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Optionally persist the app client secret in Key Vault (write-only from here).
resource "azurerm_key_vault_secret" "client_secret" {
  count           = local.use_kv && var.client_secret != "" ? 1 : 0
  name            = "${var.deployment_name}-agent-client-secret"
  value           = var.client_secret
  key_vault_id    = var.key_vault_id
  content_type    = "application/x-matillion-oauth-client-secret"
  expiration_date = var.client_secret_expiration_date
  tags            = var.tags
}

# Grant the identity read access to Key Vault secrets it needs at runtime.
resource "azurerm_role_assignment" "kv_secrets_user" {
  count                = local.use_kv ? 1 : 0
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.agent_role.principal_id
}

# ---------------------------------------------------------------------------
# Least-privilege deploy-time role (mirrors the composer contract permissions).
# ---------------------------------------------------------------------------
resource "azurerm_role_definition" "deployer" {
  count       = var.create_deployer_role ? 1 : 0
  name        = "${var.deployment_name}-auth-msi-deployer"
  scope       = var.role_scope
  description = "Least-privilege permissions to provision the core/auth-msi module."

  permissions {
    actions = [
      "Microsoft.ManagedIdentity/userAssignedIdentities/write",
      "Microsoft.KeyVault/vaults/secrets/read",
    ]
    not_actions = []
  }

  assignable_scopes = [var.role_scope]
}
