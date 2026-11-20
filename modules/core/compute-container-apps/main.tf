# modules/core/compute-container-apps  (Azure)
#
# Declares the agent compute service: agent_service = azurerm_container_app named
# "{deployment_name}-agent". Mirrors the production modules/azure/container-apps
# module; kept thin so the composer path resolves. The app runs as the
# user-assigned managed identity (agent_role) from core/auth-msi, making the
# compute -> auth dependency explicit.

locals {
  size_map = {
    small  = { cpu = 1.0, memory = "2Gi" }
    medium = { cpu = 2.0, memory = "4Gi" }
    large  = { cpu = 4.0, memory = "8Gi" }
    xlarge = { cpu = 8.0, memory = "16Gi" }
  }
  cpu      = local.size_map[var.runner_size].cpu
  memory   = local.size_map[var.runner_size].memory
  app_name = "${var.deployment_name}-agent"

  # Set on the agent when disable_script_execution is true. Pointing the
  # interpreter commands at paths that do not exist makes Python Script and Bash
  # Script fail at Run. All three together are the tested set; do not drop one.
  script_execution_disabled_env = {
    SCRIPT_OOM_PROTECTION_ENABLED = "false"
    MTLN_PYTHON_3_COMMAND         = "/python-script-disabled-on-this-runner"
    MTLN_BASH_COMMAND             = "/bash-script-disabled-on-this-runner"
  }
}

resource "azurerm_container_app" "agent_service" {
  name                         = local.app_name
  container_app_environment_id = var.container_app_environment_id
  resource_group_name          = element(split("/", var.role_scope), length(split("/", var.role_scope)) - 1)
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.agent_identity_id]
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas
    container {
      name   = "agent"
      image  = var.image_url
      cpu    = local.cpu
      memory = local.memory

      dynamic "env" {
        for_each = var.disable_script_execution ? local.script_execution_disabled_env : {}
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Least-privilege deploy-time role (mirrors the composer contract permissions).
# ---------------------------------------------------------------------------
resource "azurerm_role_definition" "deployer" {
  count       = var.create_deployer_role ? 1 : 0
  name        = "${var.deployment_name}-compute-container-apps-deployer"
  scope       = var.role_scope
  description = "Least-privilege permissions to provision the core/compute-container-apps module."

  permissions {
    actions = [
      "Microsoft.App/containerApps/write",
      "Microsoft.App/containerApps/read",
      "Microsoft.Insights/logProfiles/write",
    ]
    not_actions = []
  }

  assignable_scopes = [var.role_scope]
}
