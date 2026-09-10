# addon/queue-azure-storage (Azure)

Azure Queue Storage pipeline-trigger add-on. Declares the three composer-contract
resources:

- `trigger_storage_account` — `azurerm_storage_account` (TLS1_2, no public access).
- `trigger_queue` — `azurerm_storage_queue`.
- `trigger_role_assignment` — `azurerm_role_assignment` granting the agent
  identity **Storage Queue Data Message Processor** (messages read/delete),
  ordered after the queue and the `agent_role`.

## Reconciliation with PR #119 (`feat/DPC-52314-azure-queue-adapter`)
PR #119 adds [`modules/azure/queue-adapter-job`](../../azure) — the **production**
consumer, an event-driven Container App Job scaled by KEDA (`azure-queue`
backend) that drains the queue. This composer module does **not** reimplement
that job; it provisions the storage-queue topology + the RBAC grant so the
composer path resolves. Compose #119's job on top by pointing it at this
module's `trigger_storage_account_id` (`existing_storage_account_id`,
`create_mapping_table = false`) and `trigger_queue_name`.

## Key inputs
`deployment_name`, `location` *(required)*, `resource_group_name` *(required)*,
`agent_principal_id` *(required)*, `queue_name`, `tags`.

## Outputs
`trigger_storage_account_id`, `trigger_storage_account_name`,
`trigger_queue_name`, `trigger_queue_url`, `trigger_role_assignment_id`.
