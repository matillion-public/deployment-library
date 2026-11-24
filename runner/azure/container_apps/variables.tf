variable "name" {
  type        = string
  description = "Name prefix for all resources deployed by this template. When enable_script_runner = true, maximum 11 characters — the script runner Container App name suffix (-script-runner-<6-char-salt>) consumes 21 of Azure's 32-character limit."
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
  description = "Matillion runner/agent ID from Matillion runner (Agent) details (API contract field name)"
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
  description = "Resource ID of the Azure Container Registry hosting container_image_url. Set for a private registry: grants the runner identity AcrPull on that registry and makes image pulls use the identity. Leave null for a public registry (the default image): the image pulls anonymously and no AcrPull role is assigned."
  default     = null
}

variable "runner_size" {
  type        = string
  description = "T-shirt size for the runner container: small=1vCPU/4GiB, medium=2vCPU/8GiB, large=4vCPU/16GiB, xlarge=8vCPU/32GiB. Drives container_cpu, container_memory, and workload_profile_type (D4 for small/medium/large, D8 for xlarge)."
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

variable "storage_account_replication_type" {
  type        = string
  description = "Replication for the storage account. ZRS spreads copies across availability zones and is the setting that matches zone_redundancy_enabled; LRS keeps one copy in one zone. Defaults to LRS so existing deployments plan clean — set ZRS on new deployments."
  default     = "LRS"
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

variable "enable_script_runner" {
  type        = bool
  description = "Deploy the optional shared script runner Container App alongside the runner"
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
  default     = "matillion.azurecr.io/maia-script-runner:latest"
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

variable "export_logs" {
  type        = string
  description = "Optional flag to enable log export from the runner container to Matillion. Set to 'true' to enable, 'false' to disable. Leave empty to omit."
  default     = "true"
}

variable "disable_script_execution" {
  type        = bool
  description = <<-EOT
    Stop the Python Script and Bash Script components running on this runner.
    When true the runner container gets SCRIPT_OOM_PROTECTION_ENABLED=false and
    points MTLN_PYTHON_3_COMMAND and MTLN_BASH_COMMAND at paths that do not
    exist, so both components fail at Run with "Cannot run program
    \"/python-script-disabled-on-this-runner\" ... (No such file or directory)".
    Pipelines still pass Validate. Script Pushdown is unaffected because it runs
    on the remote script runner, and certificates, drivers and Python libraries
    still load. These are internal runner settings, not a supported product
    toggle: re-test after runner upgrades.
  EOT
  default     = false
}

variable "proxy_protocol_http" {
  type        = string
  description = "Optional proxy protocol for HTTP traffic (e.g. 'http'). Leave empty to omit."
  default     = ""
}

variable "proxy_protocol_https" {
  type        = string
  description = "Optional proxy protocol for HTTPS traffic (e.g. 'https'). Leave empty to omit."
  default     = ""
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

  validation {
    condition = alltrue([
      for id in var.key_vault_administrator_principal_ids == null ? tolist([]) : tolist(var.key_vault_administrator_principal_ids) :
      can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", id))
    ])
    error_message = "Each entry in key_vault_administrator_principal_ids must be an Entra object ID (GUID), not a user principal name or display name."
  }
}

variable "key_vault_allowed_ip_ranges" {
  type        = list(string)
  description = "Public IPv4 addresses or CIDR ranges (/8 to /30) allowed through the Key Vault firewall, for example the operator's egress IP so they can add secrets. Empty keeps the vault reachable only from the deployment's subnets. A rule added with az keyvault network-rule add is removed by the next apply."
  default     = []

  validation {
    condition = alltrue([
      for r in var.key_vault_allowed_ip_ranges :
      can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}(/[0-9]{1,2})?$", r)) &&
      try(cidrsubnet(length(split("/", r)) == 2 ? r : "${r}/32", 0, 0) == (length(split("/", r)) == 2 ? r : "${r}/32"), false)
    ])
    error_message = "Each entry in key_vault_allowed_ip_ranges must be an IPv4 address (203.0.113.10) or an IPv4 CIDR with no host bits set (203.0.113.0/24)."
  }

  validation {
    condition = alltrue([
      for r in var.key_vault_allowed_ip_ranges :
      try(length(split("/", r)) == 1 || (tonumber(split("/", r)[1]) >= 8 && tonumber(split("/", r)[1]) <= 30), true)
    ])
    error_message = "key_vault_allowed_ip_ranges CIDRs must have a prefix between /8 and /30. Give a single host as a plain address (203.0.113.10), not /32: Key Vault does not accept /31 or /32."
  }

  validation {
    condition = alltrue(flatten([
      for r in var.key_vault_allowed_ip_ranges : [
        for a in [{
          n = sum([for i, o in split(".", split("/", r)[0]) : tonumber(o) * pow(256, 3 - i)])
          p = length(split("/", r)) == 2 ? tonumber(split("/", r)[1]) : 32
          }] : [
          for b in [{ n = 167772160, p = 8 }, { n = 2886729728, p = 12 }, { n = 3232235520, p = 16 }] :
          floor(a.n / pow(2, 32 - min(a.p, b.p))) != floor(b.n / pow(2, 32 - min(a.p, b.p)))
        ]
      ] if can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}(/[0-9]{1,2})?$", r))
    ]))
    error_message = "key_vault_allowed_ip_ranges must not overlap private ranges (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16). Key Vault IP rules accept public addresses only; traffic from the deployment's subnets is allowed by the subnet rule."
  }
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
