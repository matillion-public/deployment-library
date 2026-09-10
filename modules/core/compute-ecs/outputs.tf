output "agent_service_id" {
  description = "ID of the agent ECS service. Passed to addon/script-runner and addon/queue-sqs to establish the depends-on-agent_service ordering."
  value       = aws_ecs_service.agent_service.id
}

output "agent_service_name" {
  description = "Name of the agent ECS service (\"{deployment_name}-agent\")."
  value       = aws_ecs_service.agent_service.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster hosting the agent."
  value       = aws_ecs_cluster.agent.arn
}

output "log_group_name" {
  description = "CloudWatch log group for the agent."
  value       = aws_cloudwatch_log_group.agent.name
}

output "deployer_policy_arn" {
  description = "ARN of the managed deployer policy (null when create_deployer_policy = false)."
  value       = var.create_deployer_policy ? aws_iam_policy.deployer[0].arn : null
}
