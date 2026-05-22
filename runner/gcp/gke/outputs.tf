output "cluster_name" {
  value = module.gke.cluster_name
}

output "auth_config_command" {
  value = module.gke.auth_config_command
}

output "runner_workload_sa_email" {
  description = "GCP Service Account email to set as gcp.workloadIdentity.serviceAccountEmail in Helm values"
  value       = module.gke.runner_workload_sa_email
}

output "gcs_bucket_name" {
  value = module.gke.gcs_bucket_name
}

output "secret_manager_secret_id" {
  value = module.gke.secret_manager_secret_id
}

output "nat_ip" {
  description = "Static IP address of the Cloud NAT gateway (if enabled)"
  value       = module.networking.nat_ip
}
