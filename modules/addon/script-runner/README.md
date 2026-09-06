# addon/script-runner (AWS / Azure / GCP)

The shared script runner (script pushdown). Declares `script_runner` as an ECS
Service (AWS) / Container App (Azure) / Cloud Run service (GCP) — selected via
`cloud` — named `{deployment_name}-script-runner`.

The agent reaches the runner over **SSH on port 2222**, so the runner needs **no
cloud IAM permissions of its own**. The `script_runner → agent_service`
dependency is established by referencing `agent_service_id` (from the
`core/compute-*` module) so the runner is created after the agent.

Canonical multi-arch image: `brbajematillion/maia-script-runner:current`.

## Key inputs
`cloud` *(required)*, `deployment_name`, `agent_service_id` *(required)*, `size`,
`image`, `ssh_public_key` (**sensitive**, required), plus provider-specific
placement inputs (AWS: `cluster_arn`/`subnet_ids`/`security_group_ids`; Azure:
`container_app_environment_id`/`resource_group_name`; GCP:
`project_id`/`gcp_region`/`service_account_email`).

## Outputs
`script_runner_id`, `script_runner_name`.
