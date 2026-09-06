variable "name" {
  type = string
}

# Kubernetes namespace the runner is deployed into. The Helm chart's documented
# install (runner/helm/README.md) always uses `--namespace matillion`, so the
# workload-identity federated credential subject must reference this namespace,
# NOT var.name. Overriding var.name for a client prefix previously broke AAD
# token exchange because the subject no longer matched the deployed SA.
variable "namespace" {
  type        = string
  description = "Kubernetes namespace the runner is deployed into. Must match the namespace used in Helm chart installation (default: matillion). The federated credential subject references this namespace for AAD token exchange."
  default     = "matillion"
}

# ServiceAccount names presented by the runner pods. These are fixed by the Helm
# chart (runner/helm/runner/values.yaml hardcodes `matillion-runner-sa`;
# script-runner resolves to `matillion-runner-script-runner-sa` via the chart's
# fullname helper). The federated credential subject must match these exactly.
# Exposed as variables only so a client who overrides serviceAccount.name in
# Helm can mirror it here.
variable "runner_service_account_name" {
  type        = string
  description = "ServiceAccount name for the runner pod. Must match the serviceAccount.name value in the Helm chart (default: matillion-runner-sa). The federated credential subject references this for workload identity."
  default     = "matillion-runner-sa"
}

variable "script_runner_service_account_name" {
  type        = string
  description = "ServiceAccount name for the script-runner pod. Must match the fullname helper output in the Helm chart (default: matillion-runner-script-runner-sa). The federated credential subject references this for workload identity."
  default     = "matillion-runner-script-runner-sa"
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "tags" {
  type = map(string)
}

variable "desired_node_count" {
  type    = number
  default = 2
}

variable "random_string_salt" {
  type = string
}

variable "is_private_cluster" {
  type    = bool
  default = false
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

# Empty by default so existing clusters plan clean. Azure treats a node pool's
# zones as immutable, so setting this on a cluster that already exists forces the
# default node pool to be REPLACED — see readme.md for the migration path.
variable "storage_account_replication_type" {
  type        = string
  description = "Replication for the staging storage account. ZRS spreads copies across availability zones and is what pairs with a zonal node pool; LRS keeps one copy in one zone. Defaults to LRS so existing deployments plan clean — set ZRS on new deployments. Changing this on an account that already holds data is an Azure conversion, not a Terraform edit."
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "storage_account_replication_type must be one of LRS, ZRS, GRS, GZRS, RAGRS, RAGZRS."
  }
}

variable "node_pool_zones" {
  type        = list(string)
  description = "Availability zones for the default node pool, e.g. [\"1\", \"2\", \"3\"]. Empty (the default) leaves the pool zone-unaware, meaning every node — and so every runner replica — can land in a single zone. Set this on new clusters; changing it on an existing one forces node pool replacement."
  default     = []

  validation {
    condition     = length(var.node_pool_zones) != 1
    error_message = "node_pool_zones with a single zone gives no zone redundancy while still forcing pool replacement to change later. Use at least two zones, or leave it empty."
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
  description = "Enable NAT Gateway for AKS outbound traffic"
  default     = false
}

variable "nat_gateway_public_ip" {
  type        = string
  description = "Public IP of the NAT Gateway. When set with a public cluster, it is appended to authorized_ip_ranges so node kubelet traffic egressing through the NAT can reach the API server."
  default     = null
}
variable "min_node_count" {
  description = "Autoscaler floor for the default node pool. Defaults to one node per zone in node_pool_zones, or 2 when the pool is zone-unaware. Note this floor is billed continuously, and that a floor below the zone count means zone spread is not satisfied at rest."
  type        = number
  default     = null
}

variable "max_node_count" {
  description = "Autoscaler ceiling for the default node pool. Defaults to twice desired_node_count. Size this against how many tenants can scale simultaneously — the ceiling costs nothing until it is used, whereas raising desired_node_count raises the billed floor."
  type        = number
  default     = null
}

variable "sku_tier" {
  description = "Cluster tier. Standard is required to enable AKS cost analysis (az aks update --enable-cost-analysis), which is what attributes spend per namespace and per deployment on a shared cluster. Free carries no uptime SLA."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Free, Standard or Premium."
  }
}
