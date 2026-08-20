output "service_account_email" {
  description = "Email of the runner's Google service account. Set this as gcp.workloadIdentity.serviceAccountEmail in the Helm values."
  value       = google_service_account.runner.email
}

output "service_account_id" {
  description = "Fully qualified ID of the runner's Google service account, for additional IAM bindings made outside this module."
  value       = google_service_account.runner.id
}

output "k8s_service_account_name" {
  description = "Kubernetes service account this identity is bound to. Set this as serviceAccount.name in the Helm values — the two must match or the pod gets no credentials."
  value       = var.service_account_name
}

output "scoped_secret_ids" {
  description = "Secrets this runner can read. Anything absent from this list is not readable by the runner."
  value       = var.grant_project_wide_secret_access ? ["*ALL SECRETS IN PROJECT (grant_project_wide_secret_access is true)*"] : var.secret_ids
}
