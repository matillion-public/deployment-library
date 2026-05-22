variable "name" {
  type        = string
  description = "Name prefix for all resources deployed by this template"
}

variable "azure_subscription_id" {
  type        = string
  description = "The Azure subscription ID"
}

variable "azure_tenant_id" {
  type        = string
  description = "The Azure tenant ID"
}

variable "location" {
  type        = string
  description = "Azure region for resource deployment"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group to deploy into"
}

variable "account_id" {
  type        = string
  description = "Matillion Account ID from Matillion runner (Agent) details"
}

variable "agent_id" {
  type        = string
  description = "Matillion Agent ID from Matillion runner (Agent) details (API contract field name)"
}

variable "client_id" {
  type        = string
  description = "OAuth client_id from Matillion runner credentials"
  sensitive   = true
}

variable "client_secret" {
  type        = string
  description = "OAuth client_secret from Matillion runner credentials"
  sensitive   = true
}

variable "matillion_cloud_region" {
  type        = string
  description = "Matillion regional endpoint (e.g. eu1, us1)"
}

variable "container_image_url" {
  type        = string
  description = "Container image URL for the Matillion runner"
  default     = "matillion.azurecr.io/cloud-agent:current"
}

variable "runner_size" {
  type        = string
  description = "T-shirt size for the agent container: small=1vCPU/4GiB, medium=2vCPU/8GiB, large=4vCPU/16GiB, xlarge=8vCPU/32GiB. Drives container_cpu, container_memory, and workload_profile_type (D4 for small/medium/large, D8 for xlarge)."
  default     = "small"
  validation {
    condition     = contains(["small", "medium", "large", "xlarge"], var.runner_size)
    error_message = "runner_size must be one of: small, medium, large, xlarge."
  }
}

variable "workload_profile_type" {
  type        = string
  description = "Override the workload profile type derived from runner_size. xlarge requires at least D8."
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
  description = "Override the CPU allocation derived from runner_size."
  default     = null
}

variable "container_memory" {
  type        = string
  description = "Override the memory allocation derived from runner_size (e.g. \"4Gi\")."
  default     = null
}

variable "zone_redundancy_enabled" {
  type        = bool
  description = "Enable zone redundancy for the Container App Environment"
  default     = true
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Enable NAT Gateway for controlled outbound egress"
  default     = false
}

variable "nat_gateway_idle_timeout" {
  type        = number
  description = "NAT Gateway idle timeout in minutes"
  default     = 10
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
}
