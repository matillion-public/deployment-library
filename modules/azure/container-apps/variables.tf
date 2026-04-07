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

variable "workload_profile_type" {
  type        = string
  description = "Workload profile type for the Container App Environment (e.g. D4, D8)"
  default     = "D4"
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
  description = "CPU allocation for the container"
  default     = "1.0"
}

variable "container_memory" {
  type        = string
  description = "Memory allocation for the container"
  default     = "4Gi"
}

variable "zone_redundancy_enabled" {
  type        = bool
  description = "Enable zone redundancy for the Container App Environment"
  default     = true
}
