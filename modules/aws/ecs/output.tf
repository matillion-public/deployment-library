output "ECSCluster" {
  value = aws_ecs_cluster.matillion_dpc_cluster.name
}

output "RunnerSecret" {
  value = var.runner_secret_arn
}

output "ECSService" {
  value = aws_security_group.ecs_security_group.name
}

output "script_runner_endpoint" {
  description = "Service Connect DNS endpoint for the script runner (only set when enable_script_runner = true)."
  value       = var.enable_script_runner ? "script-runner:2222" : ""
}
