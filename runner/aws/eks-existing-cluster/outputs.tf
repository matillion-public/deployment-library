output "cluster_name" {
  description = "The cluster the runner goes into."
  value       = var.cluster_name
}

output "namespace" {
  description = "Install the runner chart into this namespace (helm --namespace)."
  value       = local.namespace
}

output "service_account_name" {
  description = "Set as serviceAccount.name in the chart values. The IAM role trusts only this name."
  value       = local.service_account_name
}

output "script_runner_service_account_name" {
  description = "Set as scriptRunner.serviceAccount.name in the chart values."
  value       = local.script_runner_service_account_name
}

output "service_account_role_arn" {
  description = "Set as serviceAccount.roleArn in the chart values."
  value       = module.identity.role_arn
}

output "script_runner_role_arn" {
  description = "Set as scriptRunner.serviceAccount.roleArn in the chart values. It has the runner's buckets and no secrets."
  value       = module.script_runner_identity.role_arn
}

output "region" {
  description = "Set as aws.region in the chart values. Pods on Fargate can't look it up themselves."
  value       = var.region
}

output "secret_name_prefix" {
  description = "Secrets the runner creates or reads must have names starting with this."
  value       = local.secret_name_prefix
}
