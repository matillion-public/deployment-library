output "network_id" {
  description = "Cloud-neutral network identifier: the VPC ID (AWS) or network self-link/name (GCP)."
  value       = local.is_aws ? var.vpc_id : var.network
}

output "subnet_ids" {
  description = "Cloud-neutral subnet identifiers: subnet IDs (AWS) or the single subnetwork (GCP)."
  value       = local.is_aws ? var.subnet_ids : compact([var.subnetwork])
}

output "deployer_policy_arn" {
  description = "AWS: ARN of the least-privilege deployer managed policy (null otherwise)."
  value       = local.is_aws && var.create_deployer_policy ? aws_iam_policy.deployer[0].arn : null
}

output "deployer_role_id" {
  description = "GCP: ID of the least-privilege deployer custom role (null otherwise)."
  value       = local.is_gcp && var.create_deployer_policy ? google_project_iam_custom_role.deployer[0].id : null
}
