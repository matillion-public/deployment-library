output "agent_service_account_email" {
  description = "Email of the agent service account. Passed to core/compute-cloud-run as agent_service_account_email."
  value       = google_service_account.agent_role.email
}

output "agent_service_account_id" {
  description = "Fully-qualified ID of the agent service account."
  value       = google_service_account.agent_role.id
}

output "agent_service_account_key" {
  description = "Base64-encoded service account key JSON (null unless create_service_account_key = true). Sensitive."
  value       = var.create_service_account_key ? google_service_account_key.agent_role[0].private_key : null
  sensitive   = true
}

output "deployer_role_id" {
  description = "ID of the least-privilege deployer custom role (null when create_deployer_role = false)."
  value       = var.create_deployer_role ? google_project_iam_custom_role.deployer[0].id : null
}
