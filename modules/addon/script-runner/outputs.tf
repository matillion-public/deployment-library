output "script_runner_id" {
  description = "ID of the script runner service (provider-native)."
  value = local.is_aws ? try(aws_ecs_service.script_runner[0].id, null) : (
    local.is_azure ? try(azurerm_container_app.script_runner[0].id, null) :
    try(google_cloud_run_v2_service.script_runner[0].id, null)
  )
}

output "script_runner_name" {
  description = "Name of the script runner service (\"{deployment_name}-script-runner\")."
  value       = "${var.deployment_name}-script-runner"
}
