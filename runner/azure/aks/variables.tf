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

variable "namespace" {
  type        = string
  description = "Kubernetes namespace the runner is installed into. The workload identity federated credentials are bound to this namespace, so it must equal the namespace used for `helm install`. Changing it on an existing deployment updates the subject of both federated credentials in place."
  default     = "matillion"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid Kubernetes namespace: lowercase letters, digits and hyphens, starting and ending with a letter or digit, up to 63 characters."
  }
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

variable "grant_runner_subscription_reader" {
  type        = bool
  description = "Grant the shared runner identity Reader on the whole subscription. Only takes effect when the shared identity is created (workload_identity_enabled and create_runner_identity). Planning and applying this grant needs Microsoft.Authorization/roleAssignments/read and roleAssignments/write at subscription scope from whoever runs Terraform. Set false when that principal is scoped to the resource group. Running pipelines without this grant has not been tested. Setting false on an existing deployment destroys the assignment, which needs roleAssignments/delete at subscription scope."
  default     = true
  nullable    = false
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

variable "enable_container_insights" {
  type        = bool
  description = "Create a Log Analytics workspace and connect the cluster to it with the oms_agent addon (Container Insights). False, the default, creates neither, so no workspace is billed or left soft-deleted after destroy. Container Insights bills for the data ingested into the workspace. Enabling it on an existing cluster is applied by the azurerm provider as an update to the cluster's oms_agent block."
  default     = false
}

variable "enable_key_vault_secrets_provider" {
  type        = bool
  description = "Enable the azure-keyvault-secrets-provider addon (Secrets Store CSI driver for Key Vault) with secret rotation on, so the runner chart's config.existingSecret can be filled from Key Vault and picks up rotated values. False, the default, leaves the addon off; an addon enabled outside Terraform, with az aks enable-addons, is then removed on the next apply. See \"Key Vault secrets provider\" in modules/azure/aks/readme.md."
  default     = false
}

variable "azure_rbac_enabled" {
  description = "Enable Microsoft Entra ID integration and Azure RBAC for Kubernetes authorization. Default false keeps the cluster as it is today: no Entra integration. When true, kubectl and helm need kubelogin and an Azure role assignment on the cluster or membership of a group in admin_group_object_ids. See \"Cluster access\" in modules/azure/aks/readme.md."
  type        = bool
  default     = false
}

variable "admin_group_object_ids" {
  description = "Object IDs of Entra ID groups whose members get cluster-admin through Kubernetes RBAC. Only used when azure_rbac_enabled is true. May be empty: access is then granted only through Azure RBAC role assignments on the cluster."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for id in var.admin_group_object_ids : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))])
    error_message = "admin_group_object_ids must contain Entra ID group object IDs (GUIDs)."
  }
}

variable "local_account_disabled" {
  description = "Disable the cluster's local accounts, which removes the admin kubeconfig that Contributor on the cluster can otherwise download. Requires azure_rbac_enabled = true. Default false keeps local accounts enabled. See \"Cluster access\" in modules/azure/aks/readme.md before enabling."
  type        = bool
  default     = false
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

variable "https_inbound_source_prefixes" {
  type        = list(string)
  description = "Sources allowed inbound on TCP 443 by the NSG on the created subnets. [\"*\"] (default) allows any source. Set IP addresses or CIDR ranges to restrict it, or [] to remove the rule when nothing in the cluster takes inbound 443 from outside the VNet. Ignored when existing_subnet_ids is set, since the subnets and their NSG are then not managed here."
  default     = ["*"]
  nullable    = false
}

variable "key_vault_administrator_principal_ids" {
  description = <<-EOT
    Object IDs of the users, groups or service principals granted Key Vault
    Administrator on the vault. Null (default) grants the identity running
    Terraform, so the grant follows whoever applies. A set replaces that grant
    with one per listed ID; the identity running Terraform must be in the set or
    must manage the vault some other way. An empty set grants no administrator.
    Values must be known at plan time.
  EOT
  type        = set(string)
  default     = null
}

variable "purge_key_vault_on_destroy" {
  description = "Whether terraform destroy purges the Key Vault after deleting it. When false, the vault is left soft-deleted for 7 days and its name cannot be reused for a new vault until then (a vault with the same name is recovered, not recreated). When true, the identity running terraform needs the Microsoft.KeyVault/locations/deletedVaults/purge/action permission at subscription scope, which a Contributor or Owner role on the resource group does not include; without it destroy fails with a 403 after deleting everything else."
  type        = bool
  nullable    = false
  default     = false
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
