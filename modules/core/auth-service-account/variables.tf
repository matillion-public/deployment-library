variable "deployment_name" {
  description = "Deployment name prefix. Used to derive the service account ID (6-30 chars, lowercase)."
  type        = string
  default     = "matillion-agent"
}

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "create_service_account_key" {
  description = "Whether to create an exportable service account key (serviceAccountKey secret). Prefer Workload Identity — keys are a last resort."
  type        = bool
  default     = false
}

variable "create_deployer_role" {
  description = "Create the least-privilege custom IAM role describing the deploy-time permissions this module needs."
  type        = bool
  default     = true
}
