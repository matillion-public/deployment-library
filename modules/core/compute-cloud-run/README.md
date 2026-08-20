# core/compute-cloud-run (GCP)

Declares the agent compute service — `agent_service` =
`google_cloud_run_v2_service` named `{deployment_name}-agent`. The service runs
as the agent service account (`agent_role`) from
[`core/auth-service-account`](../auth-service-account), making the
**compute → auth** dependency explicit.

Least-privilege deployer custom role mirrors the composer contract:
`run.services.create/update/get`, `logging.logEntries.create`.

## Key inputs
`deployment_name`, `project_id` *(required)*, `region` *(required)*, `image_url`,
`agent_service_account_email` *(required)*, `runner_size`, `min_instances`,
`max_instances`, `create_deployer_role`, `labels`.

## Outputs
`agent_service_id`, `agent_service_name`, `agent_service_uri`, `deployer_role_id`.
