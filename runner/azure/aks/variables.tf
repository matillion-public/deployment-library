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

variable "network_plugin_mode" {
  type        = string
  description = "Azure CNI mode: \"overlay\", or null (the default) for node-subnet mode. Required for the Cilium data plane. Adding overlay to an existing cluster is an in-place Azure CNI migration that reimages every node; removing it forces the cluster to be replaced. See the \"Network policy\" section of modules/azure/aks/readme.md."
  default     = null

  validation {
    condition     = var.network_plugin_mode == null || var.network_plugin_mode == "overlay"
    error_message = "network_plugin_mode must be \"overlay\", or null for node-subnet mode."
  }
}

variable "pod_cidr" {
  type        = string
  description = "Pod address range under overlay, e.g. \"10.244.0.0/16\". Only valid with network_plugin_mode = \"overlay\"; null lets AKS use its default of 10.244.0.0/16. Once set, changing it forces the cluster to be replaced. See the \"Network policy\" section of modules/azure/aks/readme.md."
  default     = null
}

variable "network_policy" {
  type        = string
  description = "Engine that enforces the runner chart's NetworkPolicies: azure, calico or cilium. Null (the default) installs no engine, so the policies are stored and not enforced. cilium needs network_data_plane = \"cilium\" and network_plugin_mode = \"overlay\". Adding an engine to an existing cluster reimages its nodes; azure or calico can later move to cilium in place, but changing to any other engine replaces the cluster. Setting this back to null leaves an installed engine in place. See the \"Network policy\" section of modules/azure/aks/readme.md."
  default     = null

  validation {
    condition     = var.network_policy == null || contains(["azure", "calico", "cilium"], coalesce(var.network_policy, "none"))
    error_message = "network_policy must be azure, calico or cilium, or null for no policy engine."
  }
}

variable "network_data_plane" {
  type        = string
  description = "Pod networking data plane: azure (the default) or cilium. cilium is required for network_policy = \"cilium\". Moving an existing cluster from azure to cilium is an in-place upgrade that reimages every node; moving back replaces the cluster. See the \"Network policy\" section of modules/azure/aks/readme.md."
  default     = "azure"

  validation {
    condition     = contains(["azure", "cilium"], var.network_data_plane)
    error_message = "network_data_plane must be azure or cilium."
  }
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

variable "min_node_count" {
  description = "Autoscaler floor for the default node pool. Null defaults to one node per zone in node_pool_zones, or 2 when the pool is zone-unaware. This floor runs continuously, so it is the part of the pool that is always billed."
  type        = number
  default     = null
}

variable "max_node_count" {
  description = "Autoscaler ceiling for the default node pool. Null defaults to double desired_node_count. Size it against how many tenants can scale at once — the ceiling costs nothing until it is used, unlike desired_node_count, which raises the billed floor."
  type        = number
  default     = null
}

variable "sku_tier" {
  description = "Cluster tier: Free, Standard or Premium. Standard is required to enable AKS cost analysis (az aks update --enable-cost-analysis), which attributes spend per namespace and per deployment on a cluster shared between tenants. Free carries no uptime SLA."
  type        = string
  default     = "Standard"
}

variable "existing_subnet_ids" {
  description = "Subnets to place the AKS node pool in, when the VNet is managed outside this configuration — the usual case in an enterprise landing zone where a network team owns it. Leave empty to have the networking module create a VNet, subnets and optional NAT gateway. The subnets must already allow outbound access to the Azure control plane and to the container registries the nodes pull from."
  type        = list(string)
  default     = []
}

variable "service_endpoints" {
  description = "Service endpoints on the created subnets. Storage and Key Vault are always needed; add Microsoft.ServiceBus for that queue backend, and Microsoft.ContainerRegistry for a network-restricted ACR. Ignored when existing_subnet_ids is set, since the subnet is then not managed here."
  type        = list(string)
  default     = ["Microsoft.Storage", "Microsoft.KeyVault"]
}

###############################################################################
# Resource naming.                                                            #
#                                                                             #
# Leave naming_tokens null and every resource keeps the name this root         #
# generates today. Set it to adopt an organisation's naming standard; see      #
# modules/azure/naming/README.md for the token and format model.               #
###############################################################################

variable "naming_tokens" {
  description = <<-EOT
    Tokens substituted into the resource-name formats — the switch that turns
    naming on. Null (the default) keeps today's generated names, which matters
    because a naming module fed empty tokens would generate bare type codes and
    rename every resource in an existing deployment.
  EOT
  type = object({
    bu        = optional(string, "")
    env       = optional(string, "")
    env_short = optional(string, "")
    region    = optional(string, "")
    purpose   = optional(string, "")
    instance  = optional(string, "")
  })
  default = null
}

variable "naming_formats" {
  description = "Format string per name form, passed to modules/azure/naming. Ignored when naming_tokens is null."
  type        = map(string)
  default     = {}
}

variable "naming_resource_specs" {
  description = "Per-resource spec overrides, merged per attribute into the built-in table. Ignored when naming_tokens is null."
  type = map(object({
    type       = optional(string)
    form       = optional(string)
    max_length = optional(number)
    lower      = optional(bool)
    purpose    = optional(string)
  }))
  default = {}
}

variable "naming_overrides" {
  description = "Final resource names by key, bypassing the formats entirely. Ignored when naming_tokens is null."
  type        = map(string)
  default     = {}
}
