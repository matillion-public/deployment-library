output "cluster_name" {
  value = google_container_cluster.gke_cluster.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.gke_cluster.endpoint
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = google_container_cluster.gke_cluster.master_auth[0].cluster_ca_certificate
  sensitive = true
}

output "agent_workload_sa_email" {
  value = google_service_account.agent_workload_sa.email
}

output "gcs_bucket_name" {
  value = google_storage_bucket.staging.name
}

output "secret_manager_secret_id" {
  value = google_secret_manager_secret.agent_secret.secret_id
}

output "auth_config_command" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.gke_cluster.name} --region ${var.region} --project ${var.project_id}"
}
