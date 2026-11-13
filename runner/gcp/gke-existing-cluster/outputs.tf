output "cluster_name" {
  description = "The cluster the runner goes into."
  value       = data.google_container_cluster.this.name
}

output "namespace" {
  description = "Install the runner chart into this namespace (helm --namespace)."
  value       = local.namespace
}

output "service_account_name" {
  description = "Set as serviceAccount.name in the chart values. Workload Identity binds only this name."
  value       = local.service_account_name
}

output "script_runner_service_account_name" {
  description = "Set as scriptRunner.serviceAccount.name in the chart values."
  value       = local.script_runner_service_account_name
}

output "service_account_email" {
  description = "Set as gcp.workloadIdentity.serviceAccountEmail in the chart values."
  value       = module.identity.service_account_email
}

output "script_runner_service_account_email" {
  description = "Set as scriptRunner.serviceAccount.serviceAccountEmail in the chart values. It has the runner's buckets and no secrets."
  value       = module.script_runner_identity.service_account_email
}

output "project_id" {
  description = "Set as dpcAgent.dpcAgent.env.defaultGcpProject in the chart values. The runner keeps its secrets here."
  value       = var.project_id
}

output "secret_name_prefix" {
  description = "Secrets the runner reads or updates must have IDs starting with this."
  value       = local.secret_name_prefix
}
