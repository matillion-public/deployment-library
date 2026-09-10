variable "deployment_name" {
  description = "Deployment name prefix. The agent service is named \"{deployment_name}-agent\"."
  type        = string
  default     = "matillion-agent"
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "image_url" {
  description = "DPC agent container image."
  type        = string
  default     = "public.ecr.aws/matillion/etl-agent:current"
}

variable "agent_role_arn" {
  description = "ARN of the agent IAM role from core/auth-iam. Used as the ECS task role — this input establishes the compute -> auth (agent_role) dependency."
  type        = string
}

variable "execution_role_arn" {
  description = "ARN of the ECS task execution role (image pull + log push). Defaults to agent_role_arn when empty."
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Subnets the agent service runs in (from core/networking-vpc)."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups applied to the agent service tasks."
  type        = list(string)
  default     = []
}

variable "account_id" {
  description = "Matillion account ID (from core/matillion-link)."
  type        = string
  default     = ""
}

variable "agent_id" {
  description = "Matillion agent ID (from core/matillion-link)."
  type        = string
  default     = ""
}

variable "matillion_region" {
  description = "Matillion control-plane region (from core/matillion-link)."
  type        = string
  default     = "eu1"
}

variable "desired_count" {
  description = "Desired agent replica count (from core/scaling.desired_agents)."
  type        = number
  default     = 1
}

variable "runner_size" {
  description = "T-shirt size mapping to a Fargate-valid cpu/memory pair."
  type        = string
  default     = "small"
  validation {
    condition     = contains(["small", "medium", "large", "xlarge"], var.runner_size)
    error_message = "runner_size must be one of: small, medium, large, xlarge."
  }
}

variable "log_retention_days" {
  description = "CloudWatch log retention (days)."
  type        = number
  default     = 365
}

variable "log_kms_key_arn" {
  description = "Optional KMS key ARN to encrypt the agent log group. Empty uses the default CloudWatch encryption."
  type        = string
  default     = ""
}

variable "create_deployer_policy" {
  description = "Create the least-privilege managed policy describing the deploy-time permissions this module needs."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to created resources."
  type        = map(string)
  default     = {}
}
