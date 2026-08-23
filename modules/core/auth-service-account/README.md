# core/auth-service-account (GCP)

**FOUNDATION** module. Creates the agent service account (`agent_role` =
`google_service_account`) that [`core/compute-cloud-run`](../compute-cloud-run)
runs the agent as. An exportable key (`serviceAccountKey` secret) is created
**only** when `create_service_account_key = true` — Workload Identity is the
preferred, keyless default.

Least-privilege deployer custom role mirrors the composer contract:
`iam.serviceAccounts.create/actAs`, `secretmanager.versions.access`.

## Key inputs
`deployment_name`, `project_id` *(required)*, `create_service_account_key`,
`create_deployer_role`.

## Outputs
`agent_service_account_email`, `agent_service_account_id`,
`agent_service_account_key` (sensitive), `deployer_role_id`.
