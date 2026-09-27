variable "deployment_name" {
  description = "Deployment name prefix. The agent container app is named \"{deployment_name}-agent\"."
  type        = string
  default     = "matillion-agent"
}

variable "container_app_environment_id" {
  description = "ID of the Container App Environment to run the agent in."
  type        = string
}

variable "image_url" {
  description = "DPC agent container image."
  type        = string
  default     = "public.ecr.aws/matillion/etl-agent:current"
}

variable "agent_identity_id" {
  description = "Resource ID of the user-assigned managed identity from core/auth-msi (agent_role). Establishes the compute -> auth dependency."
  type        = string
}

variable "runner_size" {
  description = "T-shirt size mapping to a Container Apps cpu/memory pair."
  type        = string
  default     = "small"
  validation {
    condition     = contains(["small", "medium", "large", "xlarge"], var.runner_size)
    error_message = "runner_size must be one of: small, medium, large, xlarge."
  }
}

variable "min_replicas" {
  description = "Minimum agent replicas (from core/scaling.min_agents)."
  type        = number
  default     = 1
}

variable "max_replicas" {
  description = "Maximum agent replicas (from core/scaling.max_agents)."
  type        = number
  default     = 5
}

variable "role_scope" {
  description = "Scope (subscription or resource-group ID) for the least-privilege deployer role definition and its assignable_scopes."
  type        = string
}

variable "create_deployer_role" {
  description = "Create the least-privilege custom role definition describing the deploy-time permissions this module needs."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to created resources."
  type        = map(string)
  default     = {}
}
