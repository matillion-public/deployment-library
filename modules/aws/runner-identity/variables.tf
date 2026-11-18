variable "name" {
  type        = string
  description = "Name prefix for this runner's identity resources. Use something that identifies the tenant, e.g. 'grid' or 'retail'."
}

variable "oidc_issuer_url" {
  type        = string
  description = "OIDC issuer URL of the EKS cluster (the cluster's identity[0].oidc[0].issuer). An IAM OIDC provider must already exist for this issuer — IRSA silently fails to issue credentials without one."
}

variable "partition" {
  type        = string
  description = "AWS partition. 'aws' for commercial regions, 'aws-us-gov' for GovCloud, 'aws-cn' for China."
  default     = "aws"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace this runner is deployed into"
}

variable "service_account_name" {
  type        = string
  description = "Kubernetes service account name for the runner pod. Must match serviceAccount.name in the Helm values exactly — the trust policy names this subject and nothing else."
}

variable "script_runner_service_account_name" {
  type        = string
  description = "Kubernetes service account name for the script runner pod. Empty omits it from the trust policy."
  default     = ""
}

variable "secret_arns" {
  type        = list(string)
  description = "Secrets Manager ARNs this runner may read, read only. To let the runner also save secrets created in Matillion, use secret_name_prefix."
  default     = []
}

variable "secret_name_prefix" {
  type        = string
  description = <<-EOT
    Secrets whose names start with this the runner may read, create and update, such as
    "matillion/finance/". This is what lets a runner shared with other business units
    still save secrets created in Matillion: a secret's name has to start with the
    prefix, and anything else is refused. Secrets Manager can't limit ListSecrets to
    some secrets, so every secret's metadata stays listable (name, description, tags,
    KMS key ID), but not values outside the prefix. Empty gives no such access.
  EOT
  default     = ""

  validation {
    # Exactly two segments, each closed by "/": then no valid prefix can contain another.
    # "matillion/fin" would also match "matillion/finance/", and "matillion/" every
    # runner's secrets.
    condition     = var.secret_name_prefix == "" || can(regex("^[a-zA-Z0-9_+=.@-]+/[a-zA-Z0-9_+=.@-]+/$", var.secret_name_prefix))
    error_message = "secret_name_prefix must be two segments each ending in \"/\", such as \"matillion/finance/\", so it can't also match another runner's secrets."
  }
}

variable "s3_bucket_arns" {
  type        = list(string)
  description = "S3 bucket ARNs the runner may use for staging. Object-level access is derived from each bucket ARN."
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the IAM role"
  default     = {}
}

variable "resource_names" {
  description = <<-EOT
    Resource key to explicit name, overriding the generated default. Intended to be
    fed the `names` output of modules/aws/naming, which builds them from a token
    convention. Any key left out keeps its existing generated name, so an empty map
    is exactly today's behaviour.
  EOT
  type        = map(string)
  default     = {}
}
