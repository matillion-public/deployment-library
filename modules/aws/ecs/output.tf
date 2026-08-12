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
  description = "Cloud Map (Route 53) DNS endpoint for the script runner, resolvable from anywhere in the VPC and stable across task replacement (only set when enable_script_runner = true)."
  value       = var.enable_script_runner ? "script-runner.${aws_service_discovery_private_dns_namespace.cluster_namespace[0].name}:2222" : ""
}
