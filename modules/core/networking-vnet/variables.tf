variable "deployment_name" {
  description = "Deployment name prefix."
  type        = string
  default     = "matillion-agent"
}

variable "vnet_name" {
  description = "Name of the existing VNet the agent deploys into."
  type        = string
}

variable "subnet_name" {
  description = "Name of the existing subnet the agent service uses."
  type        = string
}

variable "role_scope" {
  description = "Scope (subscription or resource-group ID) for the least-privilege deployer role definition."
  type        = string
}

variable "create_deployer_role" {
  description = "Create the least-privilege custom role definition describing the deploy-time permissions this module needs."
  type        = bool
  default     = true
}
