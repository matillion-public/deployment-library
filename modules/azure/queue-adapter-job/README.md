# Azure Queue Adapter Job (`modules/azure/queue-adapter-job`)

Azure equivalent of [`modules/aws/lambda/sqs-dpc-adapter`](../../aws/lambda/sqs-dpc-adapter).
Runs the queue→Maia Foundations pipeline-trigger adapter as an **event-driven
Container App Job** scaled by a **KEDA `azure-servicebus`** rule: the platform
starts an execution when the Service Bus queue has depth, the adapter drains it
and exits (scale-to-zero between bursts).

Provisions:

- A **user-assigned managed identity** for the job, with role assignments:
  `AcrPull` (image), `Key Vault Secrets User` (OAuth secret),
  `Azure Service Bus Data Receiver` (consume queue) on the Service Bus backend or
  `Storage Queue Data Contributor` on the source and poison queues on the storage
  backend, and `Storage Table Data Reader` (project mapping).
- An optional **Service Bus namespace + queue** (duplicate detection + native
  dead-lettering for SQS-FIFO parity), or BYO via `existing_servicebus_*`, plus a
  queue-scoped **Listen-only SAS rule** for the KEDA scaler.
- An optional **Storage account + table** for project mappings, or BYO. On the
  storage backend it also creates the source queue and its `<queue>-poison`
  companion — Storage Queues have no native DLQ, so the adapter copies
  undeliverable messages there rather than losing them.
- The **Container App Job** wired to the adapter image, with all `MATILLION_*`
  env vars and the KEDA scale rule.

## Auth model

Message consumption, secret retrieval, and table reads all use the job's
**managed identity** (no connection strings) — the adapter authenticates with
`DefaultAzureCredential` and the injected `AZURE_CLIENT_ID`.

The **KEDA scaler** (which polls queue depth to decide when to start jobs) is the
one place a connection string is still required, because Container Apps KEDA
scaler managed-identity auth is not yet exposed by the `azurerm` provider. It is
surfaced as the `queue-connection` job secret.

Where the connection string comes from depends on the setup:

| Setup | Scaler credential |
| --- | --- |
| `create_queue = true`, `queue_backend = "servicebus"` | The module creates a **Listen-only SAS rule scoped to the queue** (`azurerm_servicebus_queue_authorization_rule.scaler`) and uses it. Leave `scaler_connection_string` unset. |
| BYO Service Bus queue | Pass `scaler_connection_string` from a Listen-only rule you own, ideally via a Key Vault reference. |
| `queue_backend = "storage"` | Azure Storage has no listen-only connection string, so this is an account connection string. Prefer the AKS/Helm path, whose scaler uses workload identity and needs no credential. |

Whatever is used ends up in the Container App Job secret and therefore in
**Terraform state in plaintext** — keep state encrypted and access-restricted.

RBAC for the job identity is granted at the narrowest scope available: the
**queue** (`Azure Service Bus Data Receiver` / `Storage Queue Data Contributor`)
and the **table** (`Storage Table Data Reader`), not the parent namespace or
storage account. On the storage backend the queue grant cannot be narrowed to
`Storage Queue Data Message Processor`: settling a retryable failure calls
`update_message` to re-hide the message for a backoff interval, and
dead-lettering creates and writes to the poison queue, none of which that role
permits. Because the grants are queue-scoped, the poison queue takes its own
assignment — with BYO storage it must already exist, as the source queue and
mapping table already must.

## Observability of a poisoned message

A drain that dead-letters exits non-zero, so Container Apps retries the execution
up to `replica_retry_limit`. The retry finds the message already moved to
`<queue>-poison` and exits 0, which makes the **execution report `Succeeded`**
even though a message was discarded. Alert on the poison queue's depth or the
adapter's `MessagesDeadLettered` metric rather than on job execution status.

## AKS customers

For customers who run the agent via the Helm chart in their own AKS cluster,
this Terraform module is not used — the same adapter image is deployed as a KEDA
`ScaledJob` through the runner Helm chart (see `runner/helm/runner`). Both paths
share one image and one KEDA `azure-servicebus` trigger definition. The AKS path
requires the cluster's **KEDA addon** and **Workload Identity addon** to be
enabled.

## Example

```hcl
module "queue_adapter" {
  source = "../../modules/azure/queue-adapter-job"

  location                     = var.location
  resource_group_name          = var.resource_group_name
  container_app_environment_id = module.container_apps.container_app_environment_id
  image                        = "${var.acr_login_server}/maia-queue-adapter-azure:current"
  container_acr_id             = var.acr_id
  key_vault_id                 = module.container_apps.key_vault_id
  key_vault_url                = module.container_apps.key_vault_uri
  secret_name                  = "matillion-maia"

  # create_queue defaults to true, so the module mints its own Listen-only
  # scaler rule; scaler_connection_string is only needed for a BYO queue.

  matillion_api_url = "https://eu1.api.matillion.com/dpc/v1"
}
```
