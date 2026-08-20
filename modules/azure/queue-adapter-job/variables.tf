###############################################################################
# Azure Queue (Service Bus) -> Maia Foundations pipeline-trigger adapter.
#
# Azure equivalent of modules/aws/lambda/sqs-dpc-adapter. Runs the adapter as an
# event-driven Container App Job scaled by a KEDA azure-servicebus rule: the
# platform starts a job execution when the queue has depth, the adapter drains
# it and exits. The Service Bus queue and the project-mapping Table Storage
# table are each either created by this module or referenced (bring-your-own).
# The OAuth secret is always BYO (provisioned out of band in Key Vault).
###############################################################################

variable "name_prefix" {
  description = "Prefix for resource names created by this module."
  type        = string
  default     = "matillion-maia-queue-adapter"
}

variable "location" {
  description = "Azure region the resources are created in."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to create the adapter resources in."
  type        = string
}

variable "tags" {
  description = "Tags applied to all created resources."
  type        = map(string)
  default     = {}
}

# --------------------------------------------------------------------------- #
# Compute: the Container App Job runs in an existing Container Apps environment #
# (the same one as the agent/runner) and pulls the adapter image.              #
# --------------------------------------------------------------------------- #
variable "container_app_environment_id" {
  description = "ID of the Container App Environment to run the job in."
  type        = string
}

variable "workload_profile_name" {
  description = "Workload profile name in the Container App Environment."
  type        = string
  default     = "agentpool"
}

variable "image" {
  description = "Adapter container image URI, e.g. <registry>.azurecr.io/maia-queue-adapter-azure:current."
  type        = string
}

variable "container_acr_id" {
  description = "ACR resource ID for the registry hosting the image. Grants AcrPull to the job identity and wires the registry{} block. Set null for public images."
  type        = string
  default     = null
}

variable "cpu" {
  description = "vCPU for the job container."
  type        = number
  default     = 0.5
}

variable "memory" {
  description = "Memory for the job container, e.g. 1Gi."
  type        = string
  default     = "1Gi"
}

# --------------------------------------------------------------------------- #
# Source queue: create a Service Bus namespace + queue, or BYO an existing one #
# --------------------------------------------------------------------------- #
variable "create_queue" {
  description = "If true, create a Service Bus namespace and queue. If false, reference an existing namespace via existing_servicebus_namespace_id."
  type        = bool
  default     = true
}

variable "queue_name" {
  description = "Service Bus queue name to consume (created when create_queue = true)."
  type        = string
  default     = "matillion-maia-requests"
}

variable "servicebus_sku" {
  description = "Service Bus namespace SKU (Standard or Premium). Duplicate detection requires Standard+."
  type        = string
  default     = "Standard"
}

variable "existing_servicebus_namespace_id" {
  description = "Resource ID of an existing Service Bus namespace (when create_queue = false)."
  type        = string
  default     = ""
}

variable "existing_servicebus_namespace_fqdn" {
  description = "Fully-qualified namespace of the existing Service Bus, e.g. <ns>.servicebus.windows.net (when create_queue = false)."
  type        = string
  default     = ""
}

variable "max_delivery_count" {
  description = "Deliveries before a message is dead-lettered (created queue)."
  type        = number
  default     = 3
}

# --------------------------------------------------------------------------- #
# Project-mapping store: create a Storage account + table, or BYO.            #
# --------------------------------------------------------------------------- #
variable "create_mapping_table" {
  description = "If true, create a Storage account and project-mapping table. If false, reference an existing account via existing_storage_account_id."
  type        = bool
  default     = true
}

variable "mapping_table_name" {
  description = "Table Storage table name for project mappings."
  type        = string
  default     = "matillionprojectmappings"
}

variable "existing_storage_account_id" {
  description = "Resource ID of an existing Storage account (when create_mapping_table = false)."
  type        = string
  default     = ""
}

variable "existing_storage_account_url" {
  description = "Table endpoint URL of the existing Storage account, e.g. https://<acct>.table.core.windows.net (when create_mapping_table = false)."
  type        = string
  default     = ""
}

# --------------------------------------------------------------------------- #
# Maia Foundations API / OAuth (secret always BYO in Key Vault).              #
# --------------------------------------------------------------------------- #
variable "key_vault_id" {
  description = "Resource ID of the Key Vault holding the OAuth secret. The job identity is granted Key Vault Secrets User."
  type        = string
}

variable "key_vault_url" {
  description = "Key Vault URL, e.g. https://<vault>.vault.azure.net/."
  type        = string
}

variable "secret_name" {
  description = "Name of the Key Vault secret holding {client_id, client_secret} for Maia Foundations OAuth."
  type        = string
}

variable "matillion_api_url" {
  description = "Maia Foundations pipeline-execution API base URL."
  type        = string
  default     = "https://eu1.api.matillion.com/dpc/v1"
}

variable "matillion_token_url" {
  description = "OAuth token endpoint URL."
  type        = string
  default     = "https://id.core.matillion.com/oauth/dpc/token"
}

# --------------------------------------------------------------------------- #
# KEDA scaler tuning.                                                         #
# --------------------------------------------------------------------------- #
variable "min_executions" {
  description = "Minimum concurrent job executions (0 = scale to zero)."
  type        = number
  default     = 0
}

variable "max_executions" {
  description = "Maximum concurrent job executions."
  type        = number
  default     = 10
}

variable "polling_interval" {
  description = "KEDA queue-depth polling interval in seconds."
  type        = number
  default     = 30
}

variable "messages_per_execution" {
  description = "Target queue messages per job execution (KEDA messageCount)."
  type        = number
  default     = 5
}

variable "scaler_connection_string" {
  description = <<-EOT
    Connection string used ONLY by the KEDA scaler to poll queue depth. Message
    consumption itself always uses the job's managed identity.

    Leave unset when this module creates the source queue. On the servicebus
    backend it mints a queue-scoped Listen-only SAS rule; on the storage backend
    with create_mapping_table = true it uses the connection string of the account
    it just created, since the caller cannot supply one for an account that does
    not exist until apply.

    Required only for a BYO queue: a Listen-only rule's string for Service Bus
    (ideally via a Key Vault reference), or an account connection string for
    storage, which has no listen-only equivalent. Prefer the AKS/Helm path for
    the storage backend, where the scaler authenticates with workload identity
    and needs no connection string at all.

    Whatever is supplied is written to the Container App Job's secret and so is
    stored in plaintext in Terraform state; keep state encrypted and restricted.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

# --------------------------------------------------------------------------- #
# Queue backend selection.                                                    #
# --------------------------------------------------------------------------- #
variable "queue_backend" {
  description = "Which Azure queue the adapter consumes: 'servicebus' (ordering/dedup/DLQ parity) or 'storage' (Azure Queue Storage, lighter/METL-parity)."
  type        = string
  default     = "servicebus"
  validation {
    condition     = contains(["servicebus", "storage"], var.queue_backend)
    error_message = "queue_backend must be 'servicebus' or 'storage'."
  }
}

variable "existing_storage_queue_url" {
  description = "Storage Queue service endpoint when bringing your own storage account for the queue (storage backend, create_mapping_table = false), e.g. https://<acct>.queue.core.windows.net."
  type        = string
  default     = ""
}

variable "storage_queue_length" {
  description = "KEDA azure-queue target queue length per execution (storage backend)."
  type        = number
  default     = 5
}
