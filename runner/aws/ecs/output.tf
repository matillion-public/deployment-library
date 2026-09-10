output "ECSCluster" {
  value = module.runner.ECSCluster
}

output "RunnerSecret" {
  value = module.runner.RunnerSecret
}

output "ECSService" {
  value = module.runner.ECSService
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = data.aws_vpc.vpc.id
}

output "subnet_ids" {
  description = "The IDs of the subnets"
  value       = var.use_existing_subnet ? var.subnet_ids : aws_subnet.ecs_subnet[*].id
}

output "security_group_id" {
  description = "The ID of the security group"
  value       = var.use_existing_security_group ? var.security_group_ids : [aws_security_group.ecs_security_group[0].id]
}

output "script_runner_endpoint" {
  description = "Service Connect DNS endpoint for the script runner. Configure this in the runner as the SSH target."
  value       = module.runner.script_runner_endpoint
}

output "script_runner_task_role_name" {
  description = "Name of the script runner task role. Attach IAM policies to this role to give scripts run through Script Pushdown access to AWS resources, if not using script_runner_task_role_policy_arns. Empty string when enable_script_runner is false."
  value       = module.iam_roles.script_runner_task_role_name
}

output "sqs_pipeline_trigger_lambda_arn" {
  description = "ARN of the optional SQS->DPC adapter Lambda (null when disabled)."
  value       = var.enable_sqs_pipeline_trigger ? module.sqs_dpc_adapter[0].lambda_function_arn : null
}

output "sqs_pipeline_trigger_queue_arn" {
  description = "ARN of the source queue consumed by the adapter (null when disabled)."
  value       = var.enable_sqs_pipeline_trigger ? module.sqs_dpc_adapter[0].source_queue_arn : null
}
