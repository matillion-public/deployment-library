output "cloud" {
  description = "Selected cloud provider."
  value       = var.cloud
}

output "region" {
  description = "Target region for the deployment."
  value       = var.region
}

output "target_account" {
  description = "Cloud-specific target account / subscription / project identifier."
  value       = local.target_account
}

output "deployment_name" {
  description = "Deployment name used to prefix resources."
  value       = var.deployment_name
}

output "tags" {
  description = "Common tags/labels for all deployment resources."
  value       = var.tags
}
