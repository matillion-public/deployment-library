# core/compute-container-apps (Azure)

Declares the agent compute service — `agent_service` = `azurerm_container_app`
named `{deployment_name}-agent`. Mirrors the production
[`modules/azure/container-apps`](../../azure/container-apps) module; kept thin so
the composer path resolves. The app runs as the user-assigned managed identity
(`agent_role`) from [`core/auth-msi`](../auth-msi), making the **compute → auth**
dependency explicit.

Least-privilege deployer role definition mirrors the composer contract:
`Microsoft.App/containerApps/write`, `.../read`,
`Microsoft.Insights/logProfiles/write`.

## Key inputs
`deployment_name`, `container_app_environment_id` *(required)*, `image_url`,
`agent_identity_id` *(required)*, `runner_size`, `min_replicas`, `max_replicas`,
`role_scope` *(required)*, `create_deployer_role`, `tags`.

## Outputs
`agent_service_id`, `agent_service_name`, `agent_fqdn`,
`deployer_role_definition_id`.
