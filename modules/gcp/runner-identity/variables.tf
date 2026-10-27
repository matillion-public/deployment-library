variable "name" {
  type        = string
  description = "Name prefix for this runner's identity. Use something that identifies the tenant, e.g. 'grid' or 'retail'. The service account ID is \"<name>-runner\", truncated to GCP's 30-character limit, so keep names to 23 characters or fewer: two longer names sharing their first 23 characters get the same ID."
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
  description = "Secret Manager secret IDs this runner may read, read only. Each gets its own IAM member on that secret. To let the runner also save secrets created in Matillion, use secret_name_prefix."
  default     = []
}

variable "grant_project_wide_secret_access" {
  type        = bool
  description = "Grant roles/secretmanager.secretAccessor at the project level rather than per secret. Correct when the project belongs to a single tenant, since the project boundary is then the tenant boundary. On a project shared between tenants it gives the runner every other tenant's secrets — list secret_ids instead. Also the option for deployments that create secrets at runtime and cannot enumerate them at plan time."
  default     = false
}

variable "secret_name_prefix" {
  type        = string
  description = <<-EOT
    Secrets whose IDs start with this the runner may read and add versions to, such
    as "matillion_finance_". This is what lets a runner sharing a project with other
    business units still save secrets created in Matillion. IAM checks creating and
    listing secrets against the project rather than the secret, so neither can be
    limited to the prefix: the runner can create a secret with any ID and list every
    secret's metadata in the project, but can't read or update a value outside the
    prefix. Secret IDs allow only letters, digits, "-" and "_", so the prefix is two
    segments without "_", each followed by "_", such as "matillion_finance_". Then
    no prefix can match another runner's secrets: "matillion_fin_" can't match
    "matillion_fin-ops_", and "matillion_" isn't accepted. Empty gives no such access.
  EOT
  default     = ""

  validation {
    # Exactly two "_"-terminated segments with no "_" inside them, so no two valid
    # prefixes can be prefixes of one another unless they are equal. Without the
    # closing "_", "matillion_fin" would match "matillion_finance_"; with one segment,
    # "matillion_" would match every runner's secrets.
    condition     = var.secret_name_prefix == "" || can(regex("^[a-zA-Z0-9-]+_[a-zA-Z0-9-]+_$", var.secret_name_prefix))
    error_message = "secret_name_prefix must be two segments of letters, digits and \"-\", each ending in \"_\", such as \"matillion_finance_\", so it can't also match another runner's secrets."
  }
}

variable "storage_bucket_names" {
  type        = list(string)
  description = "GCS buckets the runner may use for staging"
  default     = []
}

variable "resource_names" {
  description = <<-EOT
    Resource key to explicit name, overriding the generated default. Intended to be
    fed the `names` output of modules/gcp/naming, which builds them from a token
    convention. Any key left out keeps its existing generated name, so an empty map
    is exactly today's behaviour.
  EOT
  type        = map(string)
  default     = {}
}
