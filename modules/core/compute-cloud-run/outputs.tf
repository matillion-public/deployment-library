output "agent_service_id" {
  description = "ID of the agent Cloud Run service. Passed to addon modules to establish depends-on-agent_service ordering."
  value       = google_cloud_run_v2_service.agent_service.id
}

output "agent_service_name" {
  description = "Name of the agent Cloud Run service (\"{deployment_name}-agent\")."
  value       = google_cloud_run_v2_service.agent_service.name
}

output "agent_service_uri" {
  description = "URI of the agent Cloud Run service."
  value       = google_cloud_run_v2_service.agent_service.uri
}

output "deployer_role_id" {
  description = "ID of the least-privilege deployer custom role (null when create_deployer_role = false)."
  value       = var.create_deployer_role ? google_project_iam_custom_role.deployer[0].id : null
}
