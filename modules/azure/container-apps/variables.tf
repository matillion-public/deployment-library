variable "name" {
  type        = string
  description = "Resource name prefix for all resources. When enable_script_runner = true, maximum 11 characters — the script runner Container App name suffix (-script-runner-<6-char-salt>) consumes 21 of Azure's 32-character limit."
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
  description = "Matillion Agent ID (API contract field name — preserved as `agent_id` because it maps to the AGENT_ID env var consumed by the runner image)"
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

variable "matillion_environment" {
  type        = string
  description = "Matillion environment — internal use only (e.g. preprod). Leave empty for production."
  default     = ""
}

variable "container_image_url" {
  type        = string
  description = "Container image URL for the Matillion runner"
  default     = "matillion.azurecr.io/cloud-agent:current"
  validation {
    condition     = !can(regex("^https?://", var.container_image_url)) && can(regex("^[^/]+/", var.container_image_url))
    error_message = "container_image_url must be in the form registry-hostname/repository:tag with no scheme prefix (e.g. matillion.azurecr.io/image:tag)."
  }
}

variable "container_acr_id" {
  type        = string
  description = "Resource ID of the Azure Container Registry hosting container_image_url. Set for a private registry to scope AcrPull to that registry and wire identity-based pulls; leave null to retain the legacy subscription-scope AcrPull grant (public or pre-existing private registry deployments)."
  default     = null
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
  description = "Override the workload profile type derived from runner_size. Leave null to use the size map. xlarge requires at least D8."
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
  description = "Override the CPU allocation derived from runner_size. Leave null to use the size map. ACA requires whole-number vCPU values for the chosen workload profile."
  default     = null
}

variable "container_memory" {
  type        = string
  description = "Override the memory allocation derived from runner_size (e.g. \"4Gi\"). Leave null to use the size map."
  default     = null
}

variable "zone_redundancy_enabled" {
  type        = bool
  description = "Enable zone redundancy for the Container App Environment"
  default     = true
}

variable "enable_script_runner" {
  type        = bool
  description = "Deploy the optional shared script runner Container App alongside the agent"
  default     = false
}

variable "script_runner_size" {
  type        = string
  description = "T-shirt size for the script runner container: small=1vCPU/4GiB, medium=2vCPU/8GiB, large=4vCPU/16GiB, xlarge=8vCPU/32GiB"
  default     = "small"
  validation {
    condition     = contains(["small", "medium", "large", "xlarge"], var.script_runner_size)
    error_message = "script_runner_size must be one of: small, medium, large, xlarge."
  }
}

variable "script_runner_authorized_keys" {
  type        = string
  description = "SSH authorized_keys content for the script runner. Required when enable_script_runner = true."
  sensitive   = true
  default     = ""
}

variable "script_runner_image_url" {
  type        = string
  description = "Container image URL for the script runner"
  default     = "matillion.azurecr.io/maia-script-runner:current"
  validation {
    condition     = !can(regex("^https?://", var.script_runner_image_url)) && can(regex("^[^/]+/", var.script_runner_image_url))
    error_message = "script_runner_image_url must be in the form registry-hostname/repository:tag with no scheme prefix (e.g. matillion.azurecr.io/image:tag)."
  }
}

variable "script_runner_acr_id" {
  type        = string
  description = "Resource ID of the Azure Container Registry to grant AcrPull on for the script runner identity. Set when pulling from a private registry; leave null for a public registry (anonymous pull)."
  default     = null
}

variable "extension_library_location" {
  type        = string
  description = "Optional Azure Blob Storage URL for additional Python libraries. Set on both the runner and script runner containers. Leave empty to omit."
  default     = ""
}

variable "external_driver_location" {
  type        = string
  description = "Optional Azure Blob Storage URL for external JDBC drivers. Set on the runner container only. Leave empty to omit."
  default     = ""
}
