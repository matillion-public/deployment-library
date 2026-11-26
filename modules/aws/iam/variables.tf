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

variable "ecs_task_role_policy_arn" {
  description = "Optional: ARN of an IAM policy to attach to the runner task role in place of the inline policy built from templates/ecs_task_role_policy.json. When set, the ARN is attached and the inline policy is not created; the caller owns the policy content. Null keeps the inline policy."
  type        = string
  default     = null

  validation {
    condition     = var.ecs_task_role_policy_arn == null || can(regex("^arn:aws[a-z-]*:iam::(aws|[0-9]{12}):policy/.+$", var.ecs_task_role_policy_arn))
    error_message = "ecs_task_role_policy_arn must be null or an IAM policy ARN (arn:aws:iam::<account id or aws>:policy/<path and name>)."
  }
}

variable "ecs_task_execution_role_policy_arn" {
  description = "Optional: ARN of an IAM policy to attach to the task execution role in place of the inline policy granting secretsmanager:GetSecretValue on runner_secret_arn. When set, the ARN is attached and the inline policy is not created; the caller owns the policy content. Null keeps the inline policy."
  type        = string
  default     = null

  validation {
    condition     = var.ecs_task_execution_role_policy_arn == null || can(regex("^arn:aws[a-z-]*:iam::(aws|[0-9]{12}):policy/.+$", var.ecs_task_execution_role_policy_arn))
    error_message = "ecs_task_execution_role_policy_arn must be null or an IAM policy ARN (arn:aws:iam::<account id or aws>:policy/<path and name>)."
  }
}

variable "ecs_task_execution_role_keypair_policy_arn" {
  description = "Optional: ARN of an IAM policy to attach to the task execution role in place of the inline policy granting secretsmanager:GetSecretValue on runner_keypair_secret_arn. Applies only when enable_script_runner is true. When set, the ARN is attached and the inline policy is not created; the caller owns the policy content. Null keeps the inline policy."
  type        = string
  default     = null

  validation {
    condition     = var.ecs_task_execution_role_keypair_policy_arn == null || can(regex("^arn:aws[a-z-]*:iam::(aws|[0-9]{12}):policy/.+$", var.ecs_task_execution_role_keypair_policy_arn))
    error_message = "ecs_task_execution_role_keypair_policy_arn must be null or an IAM policy ARN (arn:aws:iam::<account id or aws>:policy/<path and name>)."
  }
}

variable "script_runner_extension_library_policy_arn" {
  description = "Optional: ARN of an IAM policy to attach to the script runner task role in place of the inline extension library S3 policy. Applies only when enable_script_runner is true, and is attached whether or not script_runner_extension_library_bucket_arn is set. When set, the ARN is attached and the inline policy is not created; the caller owns the policy content. Null keeps the inline policy."
  type        = string
  default     = null

  validation {
    condition     = var.script_runner_extension_library_policy_arn == null || can(regex("^arn:aws[a-z-]*:iam::(aws|[0-9]{12}):policy/.+$", var.script_runner_extension_library_policy_arn))
    error_message = "script_runner_extension_library_policy_arn must be null or an IAM policy ARN (arn:aws:iam::<account id or aws>:policy/<path and name>)."
  }
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
