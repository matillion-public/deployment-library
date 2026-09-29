variable "name" {
  description = "Name for the ECS Fargate cluster to be created for hosting your runner(s)"
  type        = string
  default     = "data-insights"
}

variable "runner_secret_arn" {
  type = string
}

variable "enable_script_runner" {
  description = "Whether to create the narrow script runner task role."
  type        = bool
  default     = false
}

variable "runner_keypair_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the runner SSH keypair. Used to scope the script runner task role and grant the execution role access."
  type        = string
  default     = ""
}

variable "script_runner_extension_library_bucket_arn" {
  description = "Optional: ARN of the S3 bucket used for extension library hydration. Grants narrowly-scoped s3:GetObject and s3:ListBucket to the script runner task role."
  type        = string
  default     = ""
}

variable "script_runner_task_role_policy_arns" {
  description = "Optional: IAM managed policy ARNs to attach to the script runner task role, granting scripts run through Script Pushdown access to AWS resources (for example arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess, or your own customer-managed policy). Empty by default, in which case the task role has no AWS permissions beyond the optional extension-library grant."
  type        = list(string)
  default     = []
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
