# core/compute-ecs (AWS)

Declares the agent compute service — `agent_service` = `aws_ecs_service` named
`{deployment_name}-agent` (Fargate). Mirrors the production
[`modules/aws/ecs`](../../aws/ecs) module; kept thin so the composer path
resolves. Also provisions the cluster, task definition and log group the service
requires.

The task role is the `agent_role` from [`core/auth-iam`](../auth-iam) (passed as
`agent_role_arn`), which makes the **compute → auth (FOUNDATION)** dependency
explicit and correctly ordered.

Least-privilege deployer policy mirrors the composer contract:
`ecs:CreateService/UpdateService/DescribeServices`,
`ec2:DescribeSubnets/DescribeSecurityGroups`, `logs:CreateLogGroup`.

## Key inputs
`deployment_name`, `region`, `image_url`, `agent_role_arn` *(required)*,
`subnet_ids` *(required)*, `security_group_ids`, `desired_count`, `runner_size`,
account/agent/matillion metadata, `create_deployer_policy`, `tags`.

## Outputs
`agent_service_id`, `agent_service_name`, `cluster_arn`, `log_group_name`,
`deployer_policy_arn`.
