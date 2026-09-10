variable "deployment_name" {
  description = "Deployment name prefix. The agent service is named \"{deployment_name}-agent\"."
  type        = string
  default     = "matillion-agent"
}

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region for the Cloud Run service."
  type        = string
}

variable "image_url" {
  description = "DPC agent container image."
  type        = string
  default     = "public.ecr.aws/matillion/etl-agent:current"
}

variable "agent_service_account_email" {
  description = "Email of the agent service account from core/auth-service-account (agent_role). Establishes the compute -> auth dependency."
  type        = string
}

variable "runner_size" {
  description = "T-shirt size mapping to a Cloud Run cpu/memory pair."
  type        = string
  default     = "small"
  validation {
    condition     = contains(["small", "medium", "large", "xlarge"], var.runner_size)
    error_message = "runner_size must be one of: small, medium, large, xlarge."
  }
}

variable "min_instances" {
  description = "Minimum agent instances (from core/scaling.min_agents)."
  type        = number
  default     = 1
}

variable "max_instances" {
  description = "Maximum agent instances (from core/scaling.max_agents)."
  type        = number
  default     = 5
}

variable "create_deployer_role" {
  description = "Create the least-privilege custom IAM role describing the deploy-time permissions this module needs."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels applied to created resources."
  type        = map(string)
  default     = {}
}
