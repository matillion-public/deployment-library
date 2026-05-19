variable "name" {
  type        = string
  description = "Resource name prefix for all resources"
}

variable "location" {
  type        = string
  description = "Azure region for resource deployment"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group to deploy into"
}

variable "random_string_salt" {
  type        = string
  description = "Random string for unique resource naming"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs. Index 0 is used for the Container App Environment infrastructure subnet."

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "At least one subnet ID must be provided."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
}

variable "account_id" {
  type        = string
  description = "Matillion Account ID"
}

variable "agent_id" {
  type        = string
  description = "Matillion Agent ID"
}

variable "client_id" {
  type        = string
  description = "OAuth client_id from Matillion Agent credentials"
  sensitive   = true
}

variable "client_secret" {
  type        = string
  description = "OAuth client_secret from Matillion Agent credentials"
  sensitive   = true
}

variable "matillion_cloud_region" {
  type        = string
  description = "Matillion regional endpoint (e.g. eu1, us1)"
}

variable "container_image_url" {
  type        = string
  description = "Container image URL for the Matillion agent"
  default     = "matillion.azurecr.io/cloud-agent:current"
}

variable "agent_size" {
  type        = string
  description = "T-shirt size for the agent container: small=1vCPU/4GiB, medium=2vCPU/8GiB, large=4vCPU/16GiB, xlarge=8vCPU/32GiB. Drives container_cpu, container_memory, and workload_profile_type (D4 for small/medium/large, D8 for xlarge)."
  default     = "small"
  validation {
    condition     = contains(["small", "medium", "large", "xlarge"], var.agent_size)
    error_message = "agent_size must be one of: small, medium, large, xlarge."
  }
}

variable "workload_profile_type" {
  type        = string
  description = "Override the workload profile type derived from agent_size. Leave null to use the size map. xlarge requires at least D8."
  default     = null
}

variable "workload_profile_max_count" {
  type        = number
  description = "Maximum instance count for the workload profile"
  default     = 1
}

variable "replica_count" {
  type        = number
  description = "Number of container replicas to run (no auto-scaling on Container Apps)"
  default     = 2
}

variable "container_cpu" {
  type        = string
  description = "Override the CPU allocation derived from agent_size. Leave null to use the size map. ACA requires whole-number vCPU values for the chosen workload profile."
  default     = null
}

variable "container_memory" {
  type        = string
  description = "Override the memory allocation derived from agent_size (e.g. \"4Gi\"). Leave null to use the size map."
  default     = null
}

variable "zone_redundancy_enabled" {
  type        = bool
  description = "Enable zone redundancy for the Container App Environment"
  default     = true
}
