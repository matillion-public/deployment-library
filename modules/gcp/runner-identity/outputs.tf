output "service_account_email" {
  description = "Email of the runner's Google service account. Set this as gcp.workloadIdentity.serviceAccountEmail in the Helm values."
  value       = google_service_account.runner.email
}

output "service_account_id" {
  description = "Fully qualified ID of the runner's Google service account, for additional IAM bindings made outside this module."
  value       = google_service_account.runner.id
}

output "workload_identity_members" {
  description = "The Kubernetes service accounts, as Workload Identity principals, that can act as this service account. Nothing else can."
  value       = google_service_account_iam_binding.workload_identity.members
}

output "k8s_service_account_name" {
  description = "Kubernetes service account this identity is bound to. Set this as serviceAccount.name in the Helm values — the two must match or the pod gets no credentials."
  value       = var.service_account_name
}

output "secret_name_prefix" {
  description = "Secrets this runner can read and update must have IDs starting with this."
  value       = var.secret_name_prefix
}

output "scoped_secret_ids" {
  description = "Secrets this runner can read by ID. secret_name_prefix, when set, adds every secret under it."
  value       = var.grant_project_wide_secret_access ? ["*ALL SECRETS IN PROJECT (grant_project_wide_secret_access is true)*"] : var.secret_ids
}
