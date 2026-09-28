output "agent_role_arn" {
  description = "ARN of the agent IAM role. Passed to core/compute-ecs as the task role (establishes the compute -> auth dependency)."
  value       = aws_iam_role.agent_role.arn
}

output "agent_role_name" {
  description = "Name of the agent IAM role."
  value       = aws_iam_role.agent_role.name
}

output "auth_method" {
  description = "Configured authentication method."
  value       = var.auth_method
}

output "deployer_policy_json" {
  description = "Least-privilege deployer policy document (JSON)."
  value       = data.aws_iam_policy_document.deployer.json
}

output "deployer_policy_arn" {
  description = "ARN of the managed deployer policy (null when create_deployer_policy = false)."
  value       = var.create_deployer_policy ? aws_iam_policy.deployer[0].arn : null
}
