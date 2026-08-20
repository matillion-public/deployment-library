# modules/addon/queue-azure-storage  (Azure)
#
# Azure Queue Storage pipeline-trigger add-on. Declares the three composer-
# contract resources: trigger_storage_account, trigger_queue (storage queue),
# and trigger_role_assignment (depends on the queue and the agent_role).
#
# RECONCILIATION WITH PR #119 (feat/DPC-52314-azure-queue-adapter):
# PR #119 adds modules/azure/queue-adapter-job — the production consumer, an
# event-driven Container App Job scaled by KEDA (azure-queue backend) that drains
# the queue. This composer module does NOT reimplement that job; it provisions
# the storage-queue topology + the RBAC grant to the agent identity so the
# composer path resolves. Compose #119's job on top by pointing it at this
# module's storage account (create_mapping_table = false, existing_storage_*)
# and queue name. The role assignment here mirrors that module's
# "Storage Queue Data Message Processor" grant (messages read/delete).

locals {
  queue_name           = var.queue_name != "" ? var.queue_name : "${var.deployment_name}-triggers"
  storage_account_name = substr(replace(lower("${var.deployment_name}sa"), "/[^a-z0-9]/", ""), 0, 24)
}

resource "azurerm_storage_account" "trigger_storage_account" {
  name                            = local.storage_account_name
  location                        = var.location
  resource_group_name             = var.resource_group_name
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = var.tags
}

resource "azurerm_storage_queue" "trigger_queue" {
  name                 = local.queue_name
  storage_account_name = azurerm_storage_account.trigger_storage_account.name
}

# Grant the agent identity permission to read/delete queue messages. The scope is
# the queue's storage account and depends on the queue existing first.
resource "azurerm_role_assignment" "trigger_role_assignment" {
  scope                = azurerm_storage_account.trigger_storage_account.id
  role_definition_name = "Storage Queue Data Message Processor"
  principal_id         = var.agent_principal_id

  depends_on = [azurerm_storage_queue.trigger_queue]
}
