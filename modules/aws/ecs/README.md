# ECS Module

## Overview

This module deploys an AWS ECS cluster with a Fargate task definition and service for running Matillion ETL agents. It handles the configuration of container definitions, networking, security groups, and logging.

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
  
  name                        = "matillion-agent"
  account_id                  = var.account_id
  agent_id                    = var.agent_id
  matillion_region            = var.matillion_region
  matillion_environment       = var.matillion_environment
  region                      = var.region
  vpc_id                      = var.vpc_id
  subnet_ids                  = var.subnet_ids
  security_group_ids          = var.security_group_ids
  agent_task_role_arn         = var.agent_task_role_arn
  agent_task_role_execution_arn = var.agent_task_role_execution_arn
  agnet_secret_arn            = var.agnet_secret_arn
  desired_count               = var.desired_count
  agent_memory                = 4096
  agent_cpu                   = 1024
  ephemeral_storage_size      = 50  # Optional: Configure 50 GiB of ephemeral storage
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name for the ECS Fargate cluster | string | "data-insights" | no |
| account_id | Matillion account ID | string | n/a | yes |
| agent_id | Matillion Agent ID | string | n/a | yes |
| matillion_region | Matillion designer region | string | "eu1" | no |
| matillion_environment | Matillion environment | string | "" | no |
| region | AWS region | string | n/a | yes |
| vpc_id | VPC ID for the ECS service | string | n/a | yes |
| subnet_ids | Subnet IDs for the ECS service | list(string) | n/a | yes |
| security_group_ids | Security group IDs for the ECS service | list(string) | n/a | yes |
| agent_task_role_arn | ARN of the ECS task role | string | n/a | yes |
| agent_task_role_execution_arn | ARN of the ECS task execution role | string | n/a | yes |
| agnet_secret_arn | ARN of the agent's secret | string | n/a | yes |
| desired_count | Desired count of the agent tasks | number | 2 | no |
| create_bucket | Whether to create an S3 staging bucket | bool | true | no |
| extension_library_location | Location of the extension library | string | "" | no |
| extension_library_protocol | Protocol for the extension library | string | "" | no |
| agent_memory | Memory allocation for the agent task in MiB | number | n/a | yes |
| agent_cpu | CPU allocation for the agent task in units | number | n/a | yes |
| ephemeral_storage_size | Optional ephemeral storage size in GiB for the ECS task | number | null | no |

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
