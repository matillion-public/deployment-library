# core/auth-msi (Azure)

**FOUNDATION** module. Creates the agent managed identity (`agent_role` =
`azurerm_user_assigned_identity`, `{deployment_name}-agent-id`) that
[`core/compute-container-apps`](../compute-container-apps) runs the agent as.
Optionally stores the app `client_secret` in Key Vault and grants the identity
**Key Vault Secrets User**.

Least-privilege deployer role definition mirrors the composer contract:
`Microsoft.ManagedIdentity/userAssignedIdentities/write`,
`Microsoft.KeyVault/vaults/secrets/read`.

## Key inputs
`deployment_name`, `location` *(required)*, `resource_group_name` *(required)*,
`tenant_id`, `client_id`, `client_secret` (**sensitive**), `key_vault_id`,
`role_scope` *(required)*, `create_deployer_role`, `tags`.

## Outputs
`agent_identity_id`, `agent_identity_principal_id`, `agent_identity_client_id`,
`deployer_role_definition_id`.
