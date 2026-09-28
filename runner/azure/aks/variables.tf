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
  default = ["0.0.0.0/0"]
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

variable "storage_account_replication_type" {
  type        = string
  description = "Replication for the staging storage account. ZRS spreads copies across availability zones and is what pairs with a zonal node pool; LRS keeps one copy in one zone. Defaults to LRS so existing deployments plan clean — set ZRS on new deployments."
  default     = "LRS"
}

variable "node_pool_zones" {
  type        = list(string)
  description = "Availability zones for the default node pool, e.g. [\"1\", \"2\", \"3\"]. Empty (the default) leaves the pool zone-unaware, meaning every node — and so every runner replica — can land in a single zone. Set this on new clusters; changing it on an existing one forces node pool replacement."
  default     = []
}

variable "workload_identity_enabled" {
  type        = bool
  description = "Enable Azure Workload Identity for the runner workload (requires OIDC issuer)"
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

variable "enable_nat_gateway" {
  type        = bool
  description = "Enable NAT Gateway for controlled outbound egress with static IP"
  default     = false
}

variable "vnet_address_space" {
  type        = string
  description = "CIDR for the AKS VNet. Default 10.0.0.0/16 — set to a non-overlapping range if peering with another VNet in the same RG/subscription."
  default     = "10.0.0.0/16"
}

variable "nat_gateway_idle_timeout" {
  type        = number
  description = "NAT Gateway idle timeout in minutes (between 4 and 120)"
  default     = 10
}
