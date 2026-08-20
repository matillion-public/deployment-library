variable "name" {
  type        = string
  description = "Name prefix for this runner's identity. Use something that identifies the tenant, e.g. 'grid' or 'retail'. Truncated to fit the 30-character service account ID limit."
}

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace this runner is deployed into"
}

variable "service_account_name" {
  type        = string
  description = "Kubernetes service account name for the runner pod. Must match serviceAccount.name in the Helm values exactly — the Workload Identity binding names this member and nothing else."
}

variable "script_runner_service_account_name" {
  type        = string
  description = "Kubernetes service account name for the script runner pod. Empty omits it from the binding."
  default     = ""
}

variable "secret_ids" {
  type        = list(string)
  description = "Secret Manager secret IDs this runner may read. Each gets its own IAM member on that secret, so the runner cannot read anything not listed here."
  default     = []
}

variable "grant_project_wide_secret_access" {
  type        = bool
  description = "Grant roles/secretmanager.secretAccessor at the project level rather than per secret. Correct when the project belongs to a single tenant, since the project boundary is then the tenant boundary. On a project shared between tenants it gives the runner every other tenant's secrets — list secret_ids instead. Also the option for deployments that create secrets at runtime and cannot enumerate them at plan time."
  default     = false
}

variable "storage_bucket_names" {
  type        = list(string)
  description = "GCS buckets the runner may use for staging"
  default     = []
}
