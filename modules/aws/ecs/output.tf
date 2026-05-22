output "ECSCluster" {
  value = aws_ecs_cluster.matillion_dpc_cluster.name
}

output "RunnerSecret" {
  value = var.runner_secret_arn
}

output "ECSService" {
  value = aws_security_group.ecs_security_group.name
}
