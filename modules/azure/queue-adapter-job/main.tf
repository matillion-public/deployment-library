###############################################################################
# Resources for the Azure queue adapter. See variables.tf for the design notes.
###############################################################################

locals {
  # Resolve created-vs-BYO Service Bus and Storage references.
  servicebus_namespace_id = length(azurerm_servicebus_namespace.this) > 0 ? azurerm_servicebus_namespace.this[0].id : var.existing_servicebus_namespace_id
  servicebus_fqdn         = length(azurerm_servicebus_namespace.this) > 0 ? "${azurerm_servicebus_namespace.this[0].name}.servicebus.windows.net" : var.existing_servicebus_namespace_fqdn

  storage_account_id  = var.create_mapping_table ? azurerm_storage_account.this[0].id : var.existing_storage_account_id
  storage_account_url = var.create_mapping_table ? azurerm_storage_account.this[0].primary_table_endpoint : var.existing_storage_account_url

  # Random-free deterministic short name fragment for the storage account
  # (must be 3-24 chars, lowercase alphanumeric only).
  storage_account_name = substr(replace(lower("${var.name_prefix}sa"), "/[^a-z0-9]/", ""), 0, 24)

  # Queue backend selection.
  is_storage_backend = var.queue_backend == "storage"
  # Storage Queues have no native DLQ; the adapter dead-letters to "<queue>-poison".
  poison_queue_name = "${var.queue_name}-poison"
  storage_queue_url = var.create_mapping_table ? azurerm_storage_account.this[0].primary_queue_endpoint : var.existing_storage_queue_url

  # Exact data-plane scopes for the job identity. Granting at the namespace or
  # storage-account level would also cover every other queue and table in them.
  servicebus_queue_id     = length(azurerm_servicebus_queue.this) > 0 ? azurerm_servicebus_queue.this[0].id : "${var.existing_servicebus_namespace_id}/queues/${var.queue_name}"
  mapping_table_id        = "${local.storage_account_id}/tableServices/default/tables/${var.mapping_table_name}"
  storage_queue_id        = "${local.storage_account_id}/queueServices/default/queues/${var.queue_name}"
  storage_poison_queue_id = "${local.storage_account_id}/queueServices/default/queues/${local.poison_queue_name}"

  # The scaler polls queue depth with a connection string because azurerm does
  # not expose managed-identity scaler auth on Container App Jobs. When this
  # module creates the Service Bus queue it also mints a Listen-only rule scoped
  # to that queue, so the string cannot send or manage. On the storage backend,
  # when this module creates the storage account, it uses that account's own
  # connection string — the caller cannot supply one for an account that does not
  # exist until apply. For a BYO queue or account, the caller supplies it.
  scaler_connection_string = (
    length(azurerm_servicebus_queue_authorization_rule.scaler) > 0
    ? azurerm_servicebus_queue_authorization_rule.scaler[0].primary_connection_string
    : var.scaler_connection_string != ""
    ? var.scaler_connection_string
    : local.is_storage_backend && var.create_mapping_table
    ? azurerm_storage_account.this[0].primary_connection_string
    : ""
  )
}

# Managed identity the job runs as: pulls the image, reads the OAuth secret,
# reads the mapping table, and consumes the queue — all via RBAC, no secrets.
resource "azurerm_user_assigned_identity" "job" {
  name                = lookup(var.resource_names, "queue_adapter_identity", "${var.name_prefix}-id")
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# --------------------------------------------------------------------------- #
# Optional source queue (Service Bus namespace + queue).                      #
# --------------------------------------------------------------------------- #
resource "azurerm_servicebus_namespace" "this" {
  # checkov:skip=CKV_AZURE_203:Local auth must stay on. azurerm cannot bind a managed identity to a Container App Job scale rule, so the KEDA scaler polls depth with the queue-scoped Listen-only SAS rule created below. The job itself consumes via managed identity.
  # checkov:skip=CKV_AZURE_202:The job runs as its own user-assigned identity; a namespace-level system identity would go unused.
  # checkov:skip=CKV_AZURE_201:Customer-managed keys are Premium-SKU only; this module defaults to Standard and the queue holds only pipeline-trigger messages.
  # checkov:skip=CKV_AZURE_199:Infrastructure (double) encryption is Premium-SKU only, as above.
  # checkov:skip=CKV_AZURE_204:Disabling public network access needs Premium plus private endpoints. Customers with that requirement bring their own namespace via existing_servicebus_namespace_id.
  count               = var.create_queue && !local.is_storage_backend ? 1 : 0
  name                = lookup(var.resource_names, "servicebus_namespace", "${var.name_prefix}-sb")
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.servicebus_sku
  minimum_tls_version = "1.2"
  tags                = var.tags
}

resource "azurerm_servicebus_queue" "this" {
  count        = var.create_queue && !local.is_storage_backend ? 1 : 0
  name         = var.queue_name
  namespace_id = azurerm_servicebus_namespace.this[0].id

  # Parity with the SQS FIFO adapter: ordering, dedup, and native dead-lettering.
  requires_session                        = false
  requires_duplicate_detection            = true
  dead_lettering_on_message_expiration    = true
  max_delivery_count                      = var.max_delivery_count
  duplicate_detection_history_time_window = "PT10M"
}

# Listen-only SAS rule for the KEDA scaler, scoped to this queue rather than the
# namespace. The scaler only reads queue depth; the job consumes messages with
# its managed identity, so nothing here needs Send or Manage.
resource "azurerm_servicebus_queue_authorization_rule" "scaler" {
  count    = var.create_queue && !local.is_storage_backend ? 1 : 0
  name     = "keda-scaler-listen"
  queue_id = azurerm_servicebus_queue.this[0].id

  listen = true
  send   = false
  manage = false
}

# --------------------------------------------------------------------------- #
# Optional project-mapping store (Storage account + table).                   #
# --------------------------------------------------------------------------- #
resource "azurerm_storage_account" "this" {
  # checkov:skip=CKV2_AZURE_40:Shared Key auth must stay enabled — the storage backend's KEDA scaler needs an account connection string, and azurerm's table/queue data-plane resources use shared key. The adapter itself reads the table and queue via managed identity.
  # checkov:skip=CKV2_AZURE_41:SAS expiration policy applies to account SAS; this module issues none. The only SAS it creates is the Service Bus Listen-only rule.
  # checkov:skip=CKV2_AZURE_1:Customer-managed keys are a customer-environment decision; the account holds only the project-name-to-id mapping table.
  # checkov:skip=CKV2_AZURE_33:Private endpoints are a customer-environment decision; callers who need one bring their own account via existing_storage_account_id.
  # checkov:skip=CKV2_AZURE_38:Soft-delete applies to blob containers; this account serves only table and queue.
  # checkov:skip=CKV_AZURE_59:public_network_access_enabled must stay true — the Container App Job reaches table and queue over the public endpoint. Callers who have private endpoints bring their own account via existing_storage_account_id.
  # checkov:skip=CKV_AZURE_206:LRS is deliberate — the mapping table is redeployable configuration, not a system of record. Callers needing GRS bring their own account.
  # checkov:skip=CKV_AZURE_43:The name is assembled with replace/substr, so the rule cannot be evaluated statically; the expression already enforces lowercase alphanumeric and 24 chars.
  # checkov:skip=CKV_AZURE_33:Queue-service logging is set on the azurerm_storage_account_queue_properties resource below; the inline queue_properties block this check looks for is deprecated and goes away in azurerm v5.
  count                           = var.create_mapping_table ? 1 : 0
  name                            = lookup(var.resource_names, "queue_storage_account", local.storage_account_name)
  location                        = var.location
  resource_group_name             = var.resource_group_name
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  tags                            = var.tags
}

# Queue-service logging. Separate resource rather than the storage account's
# inline queue_properties block, which azurerm has deprecated for v5.
resource "azurerm_storage_account_queue_properties" "this" {
  count              = var.create_mapping_table ? 1 : 0
  storage_account_id = azurerm_storage_account.this[0].id

  logging {
    delete                = true
    read                  = true
    write                 = true
    version               = "1.0"
    retention_policy_days = 7
  }
}

resource "azurerm_storage_table" "mapping" {
  # checkov:skip=CKV2_AZURE_20:Table-service read logging is set through diagnostic settings against the customer's own log workspace, which this module does not own.
  count                = var.create_mapping_table ? 1 : 0
  name                 = var.mapping_table_name
  storage_account_name = azurerm_storage_account.this[0].name
}

# Source Storage Queue (storage backend only, when creating resources).
resource "azurerm_storage_queue" "source" {
  count                = var.create_mapping_table && local.is_storage_backend ? 1 : 0
  name                 = var.queue_name
  storage_account_name = azurerm_storage_account.this[0].name
}

# Companion poison queue. The adapter creates it on first dead-letter if missing,
# but pre-creating it here keeps that call an idempotent 409 and lets the role
# assignment below be scoped to the queue rather than the whole account.
resource "azurerm_storage_queue" "poison" {
  count                = var.create_mapping_table && local.is_storage_backend ? 1 : 0
  name                 = local.poison_queue_name
  storage_account_name = azurerm_storage_account.this[0].name
}

# --------------------------------------------------------------------------- #
# Role assignments for the job identity.                                      #
# --------------------------------------------------------------------------- #
resource "azurerm_role_assignment" "acr_pull" {
  count                = var.container_acr_id != null ? 1 : 0
  scope                = var.container_acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.job.principal_id
}

resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.job.principal_id
}

resource "azurerm_role_assignment" "servicebus_receiver" {
  count                = local.is_storage_backend ? 0 : 1
  scope                = local.servicebus_queue_id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_user_assigned_identity.job.principal_id
}

# Contributor, not Message Processor. The adapter settles a retryable failure with
# update_message (messages/write) to re-hide the message for a backoff interval,
# and dead-letters with create_queue + send_message against the poison queue.
# Message Processor carries only messages/read and messages/process/action, so both
# of those paths 403 — the original message is never deleted and redelivers until
# TTL, with SettlementFailures climbing and the job exiting 3.
resource "azurerm_role_assignment" "storage_queue_contributor" {
  count                = local.is_storage_backend ? 1 : 0
  scope                = local.storage_queue_id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_user_assigned_identity.job.principal_id
}

# A second assignment because the grant above is queue-scoped and does not reach a
# sibling queue. With BYO storage (create_mapping_table = false) the poison queue
# must already exist, as the source queue and mapping table already must.
resource "azurerm_role_assignment" "storage_poison_queue_contributor" {
  count                = local.is_storage_backend ? 1 : 0
  scope                = local.storage_poison_queue_id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_user_assigned_identity.job.principal_id
}

resource "azurerm_role_assignment" "table_reader" {
  scope                = local.mapping_table_id
  role_definition_name = "Storage Table Data Reader"
  principal_id         = azurerm_user_assigned_identity.job.principal_id
}

# --------------------------------------------------------------------------- #
# Container App Job — event-driven (KEDA azure-servicebus), drain-and-exit.   #
# --------------------------------------------------------------------------- #
resource "azurerm_container_app_job" "this" {
  name                         = "${var.name_prefix}-job"
  location                     = var.location
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_app_environment_id
  workload_profile_name        = var.workload_profile_name

  lifecycle {
    precondition {
      condition     = local.scaler_connection_string != ""
      error_message = "scaler_connection_string is required for a BYO queue: without it the KEDA scaler cannot poll queue depth, so the job would never start. It is derived automatically when this module creates the source queue — a queue-scoped Listen-only SAS rule on the servicebus backend, the created account's own connection string on the storage backend."
    }
  }

  # A single execution drains the queue; give it headroom then time out.
  replica_timeout_in_seconds = 1800
  replica_retry_limit        = 1

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.job.id]
  }

  # Private-registry image pulls via the job identity (AcrPull granted above).
  dynamic "registry" {
    for_each = var.container_acr_id != null ? [1] : []
    content {
      server   = split("/", var.image)[0]
      identity = azurerm_user_assigned_identity.job.id
    }
  }

  # Connection string used ONLY by the KEDA scaler to poll queue depth
  # (Service Bus or Storage account, per queue_backend). Message consumption
  # itself uses the job identity (managed identity).
  secret {
    name  = "queue-connection"
    value = local.scaler_connection_string
  }

  event_trigger_config {
    parallelism              = 1
    replica_completion_count = 1

    scale {
      min_executions              = var.min_executions
      max_executions              = var.max_executions
      polling_interval_in_seconds = var.polling_interval

      rules {
        name             = "queue-depth"
        custom_rule_type = local.is_storage_backend ? "azure-queue" : "azure-servicebus"
        metadata = local.is_storage_backend ? {
          queueName   = var.queue_name
          queueLength = tostring(var.storage_queue_length)
          } : {
          queueName    = var.queue_name
          namespace    = replace(local.servicebus_fqdn, ".servicebus.windows.net", "")
          messageCount = tostring(var.messages_per_execution)
        }
        authentication {
          secret_name       = "queue-connection"
          trigger_parameter = "connection"
        }
      }
    }
  }

  template {
    container {
      name   = "adapter"
      image  = var.image
      cpu    = var.cpu
      memory = var.memory

      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.job.client_id
      }
      env {
        name  = "MATILLION_AZURE_QUEUE_BACKEND"
        value = var.queue_backend
      }
      env {
        name  = "MATILLION_AZURE_STORAGE_QUEUE_URL"
        value = local.storage_queue_url
      }
      env {
        name  = "MATILLION_AZURE_KEY_VAULT_URL"
        value = var.key_vault_url
      }
      env {
        name  = "MATILLION_SECRET_NAME"
        value = var.secret_name
      }
      env {
        name  = "MATILLION_AZURE_STORAGE_ACCOUNT_URL"
        value = local.storage_account_url
      }
      env {
        name  = "MATILLION_PROJECT_MAPPING_TABLE"
        value = var.mapping_table_name
      }
      env {
        name  = "MATILLION_AZURE_SERVICEBUS_NAMESPACE"
        value = local.servicebus_fqdn
      }
      env {
        name  = "MATILLION_AZURE_QUEUE_NAME"
        value = var.queue_name
      }
      env {
        name  = "MATILLION_API_URL"
        value = var.matillion_api_url
      }
      env {
        name  = "MATILLION_TOKEN_URL"
        value = var.matillion_token_url
      }
    }
  }

  tags = var.tags
}
