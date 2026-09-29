# Per-runner Azure identity: one User Assigned Managed Identity per runner
# deployment, federated to that runner's Kubernetes service account, with Key
# Vault access granted one secret at a time.
#
# This exists so several business units can share one cluster and one Key Vault
# without sharing credentials. The shared-identity arrangement in
# modules/azure/aks grants "Key Vault Secrets User" at the vault scope, which
# means every runner using it can read every secret in the vault — fine for a
# single-tenant deployment, not acceptable once the vault holds another
# business unit's credentials.

data "azurerm_key_vault" "target" {
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
  for_each = toset(var.key_vault_secret_names)

  scope                = "${data.azurerm_key_vault.target.id}/secrets/${each.value}"
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.runner.principal_id
}

# Vault-scoped access, for a vault that belongs to one tenant. There the vault
# boundary is the tenant boundary and per-secret assignments add maintenance
# without adding safety. On a shared vault this hands over every other tenant's
# secrets, which is why it is opt-in rather than the default.
resource "azurerm_role_assignment" "vault_wide_secrets_user" {
  count = var.grant_vault_wide_secret_access ? 1 : 0

  scope                = data.azurerm_key_vault.target.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.runner.principal_id
}

# Reader on the vault covers metadata only — no secret values. The runner needs
# it to resolve the vault before reading anything from it. Note this does expose
# the *names* of every secret in the vault, including other tenants'.
resource "azurerm_role_assignment" "vault_reader" {
  count = var.grant_vault_reader ? 1 : 0

  scope                = data.azurerm_key_vault.target.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.runner.principal_id
}

resource "azurerm_role_assignment" "storage" {
  count = var.storage_account_id != "" ? 1 : 0

  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.runner.principal_id
}
