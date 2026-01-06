variable "name" {
  type = string
}


variable "azure_subscription_id" {
  type = string
}

variable "azure_tenant_id" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "desired_node_count" {
  type    = number
  default = 2
}

variable "is_private_cluster" {
  type    = bool
  default = true
}

variable "authorized_ip_ranges" {
  type    = list(string)
  default = [""]

}

variable "vm_size" {
  type        = string
  description = "VM size for AKS node pool"
  default     = "Standard_D4s_v4"
}

variable "node_disk_size" {
  type        = number
  description = "Node disk size in GB"
  default     = 250
}

variable "workload_identity_enabled" {
  type        = bool
  description = "Enable Azure Workload Identity for the agent workload (requires OIDC issuer)"
  default     = true
}

variable "service_principal_enabled" {
  type        = bool
  description = "Enable Service Principal authentication (alternative to Workload Identity)"
  default     = false
}

variable "service_principal_client_id" {
  type        = string
  description = "Service Principal Client ID for Key Vault access (required when service_principal_enabled is true)"
  sensitive   = true
  default     = ""
}

variable "service_principal_secret" {
  type        = string
  description = "Service Principal Secret for Key Vault access (required when service_principal_enabled is true)"
  sensitive   = true
  default     = ""
}
