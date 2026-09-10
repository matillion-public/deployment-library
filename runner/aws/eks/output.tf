output "cluster_name" {
  value = module.eks.cluster_name
}
output "cluster_subnet_ids" {
  value = module.deployment.all_subnet_ids
}

output "public_subnet_ids" {
  value = module.deployment.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.deployment.private_subnet_ids
}
output "eks_cluster" {
  value = module.eks.cluster_name

}
output "auth_config_command" {
  value = module.eks.auth_config_command

}

output "eks_cluster_arn" {
  value = module.eks.cluster_arn

}

output "service_account_role_arn" {
  value = module.eks.service_account_role_arn
}
output "sqs_pipeline_trigger_lambda_arn" {
  description = "ARN of the optional SQS->DPC adapter Lambda (null when disabled)."
  value       = var.enable_sqs_pipeline_trigger ? module.sqs_dpc_adapter[0].lambda_function_arn : null
}

output "sqs_pipeline_trigger_queue_arn" {
  description = "ARN of the source queue consumed by the adapter (null when disabled)."
  value       = var.enable_sqs_pipeline_trigger ? module.sqs_dpc_adapter[0].source_queue_arn : null
}
