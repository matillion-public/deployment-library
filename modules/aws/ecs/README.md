# ECS Module

## Overview

This module deploys an AWS ECS cluster with a Fargate task definition and service for running Matillion ETL runners. It handles the configuration of container definitions, networking, security groups, and logging.

## Features

- Creates an ECS cluster with container insights enabled
- Configures a Fargate task definition with customizable resources
- Sets up CloudWatch logging for the ECS tasks
- Supports optional ephemeral storage configuration
- Creates an ECS service with deployment circuit breaker and network configuration
- Optionally creates an S3 staging bucket with appropriate permissions

## Usage

```hcl
module "ecs" {
  source = "../../modules/aws/ecs"

  name                            = "matillion-runner"
  account_id                      = var.account_id
  agent_id                        = var.agent_id
  matillion_region                = var.matillion_region
  matillion_environment           = var.matillion_environment
  region                          = var.region
  vpc_id                          = var.vpc_id
  subnet_ids                      = var.subnet_ids
  security_group_ids              = var.security_group_ids
  runner_task_role_arn            = var.runner_task_role_arn
  runner_task_role_execution_arn  = var.runner_task_role_execution_arn
  runner_secret_arn               = var.runner_secret_arn
  desired_count                   = var.desired_count
  runner_memory                   = 4096
  runner_cpu                      = 1024
  ephemeral_storage_size          = 50  # Optional: Configure 50 GiB of ephemeral storage
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name for the ECS Fargate cluster | string | "data-insights" | no |
| account_id | Matillion account ID | string | n/a | yes |
| agent_id | Matillion runner/agent ID (API contract field name) | string | n/a | yes |
| matillion_region | Matillion designer region | string | "eu1" | no |
| matillion_environment | Matillion environment | string | "" | no |
| region | AWS region | string | n/a | yes |
| vpc_id | VPC ID for the ECS service | string | n/a | yes |
| subnet_ids | Subnet IDs for the ECS service | list(string) | n/a | yes |
| security_group_ids | Security group IDs for the ECS service | list(string) | n/a | yes |
| runner_task_role_arn | ARN of the ECS task role | string | n/a | yes |
| runner_task_role_execution_arn | ARN of the ECS task execution role | string | n/a | yes |
| runner_secret_arn | ARN of the runner's secret | string | n/a | yes |
| desired_count | Desired count of the runner tasks | number | 2 | no |
| create_bucket | Whether to create an S3 staging bucket | bool | true | no |
| extension_library_location | Location of the extension library | string | "" | no |
| extension_library_protocol | Protocol for the extension library | string | "" | no |
| runner_memory | Memory allocation for the runner task in MiB | number | n/a | yes |
| runner_cpu | CPU allocation for the runner task in units | number | n/a | yes |
| ephemeral_storage_size | Optional ephemeral storage size in GiB for the ECS task | number | null | no |
| metrics_ingress_cidr_blocks | CIDR blocks allowed to scrape the runner's Prometheus metrics. `0.0.0.0/0` is rejected | list(string) | [] | no |
| metrics_ingress_security_group_ids | Security groups allowed to scrape the runner's Prometheus metrics | list(string) | [] | no |
| metrics_ingress_ports | Metrics ports opened to those sources: 9464 (OpenTelemetry) and 8080 (deprecated `/actuator/prometheus`) | list(number) | [9464, 8080] | no |

> **Note**: `agent_id` is preserved as the input name because it maps directly to the `AGENT_ID` env var consumed by the Matillion runner image — it is part of the Matillion API contract.

## Scraping Runner Metrics

The runner serves Prometheus metrics on `:9464/metrics` (OpenTelemetry, images
built from DPC-55707 onwards) and `:8080/actuator/prometheus` (deprecated). The
task's security group has no ingress rules by default, so neither is reachable
from outside the task.

To scrape them from your own Prometheus, name its network or security group:

```hcl
metrics_ingress_security_group_ids = [aws_security_group.prometheus.id]
metrics_ingress_ports              = [9464] # OpenTelemetry only
```

This creates one ingress rule per source and port on the module's own security
group. Both endpoints are unauthenticated, so `0.0.0.0/0` is rejected. Port
8080 also serves the runner's actuator health and info endpoints, so leave it
out of `metrics_ingress_ports` if you only want metrics exposed. Tasks get
private IPs that change on each deployment, so discover them with ECS service
discovery rather than fixed targets. See
[Runner Metrics: Moving to the OpenTelemetry Endpoint](../../../blogs/runner-metrics-migration.md).

## Ephemeral Storage Configuration

The task definition supports configurable ephemeral storage for cases where the default storage provided by AWS ECS is insufficient.

### How it works

When the `ephemeral_storage_size` variable is set to a non-null value, the module will include an ephemeral storage configuration in the task definition with the specified size in GiB. If the variable is not set or is set to `null`, the task will use the default ephemeral storage provided by AWS ECS (typically 20 GiB for AWS Fargate).

### Example

```hcl
# With ephemeral storage configured
module "ecs" {
  # ... other configuration ...
  ephemeral_storage_size = 100  # 100 GiB of ephemeral storage
}

# Without ephemeral storage configured (uses default)
module "ecs" {
  # ... other configuration ...
  # ephemeral_storage_size not specified
}
```

### Limitations

- AWS Fargate tasks support ephemeral storage between 20 GiB (default) and 200 GiB.
- The ephemeral storage is temporary and will be lost when the task stops.
- There may be additional costs associated with using larger ephemeral storage sizes.

## Outputs

| Name | Description |
|------|-------------|
| cluster_arn | ARN of the created ECS cluster |
| service_arn | ARN of the created ECS service |
| task_definition_arn | ARN of the created ECS task definition |
| staging_bucket_name | Name of the created S3 staging bucket (if enabled) |
