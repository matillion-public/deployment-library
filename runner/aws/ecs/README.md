# AWS ECS Deployment for Matillion Runner

This directory contains Terraform configurations for deploying the Matillion Maia Runner using AWS ECS (Elastic Container Service) with Fargate - a serverless compute engine for containers.

## Overview

AWS ECS Fargate deployment provides:
- **Serverless Containers**: No EC2 instance management required
- **Fully Managed**: AWS handles infrastructure provisioning and scaling
- **Integrated AWS Services**: Native integration with IAM, CloudWatch, VPC
- **Flexible Scaling**: Manual and automatic scaling options
- **Cost Effective**: Pay only for resources used

### ⚠️ Task draining is limited to 120 seconds on this deployment

This is a real behavioural difference from the Kubernetes deployments, not a
tuning knob, and it should be understood before choosing ECS for workloads with
long-running pipelines.

When a task is replaced — a deployment, a scale-in, a planned failover — ECS
sends SIGTERM and then forcibly kills the container after `stopTimeout`. The
runner uses that window to finish the pipeline tasks it is already executing.

AWS documents the limit as: *"For tasks that use the Fargate launch type, the max
stop timeout value is 120 seconds and if the parameter is not specified, the
default value of 30 seconds is used"*, with *"The valid values for Fargate are
2-120 seconds"*
([ContainerDefinition API reference](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_ContainerDefinition.html)).

This deployment is Fargate-only (`requires_compatibilities = ["FARGATE"]`), so
the cap applies with no way around it. Only the EC2 launch type can exceed 120
seconds, via the `ECS_CONTAINER_STOP_TIMEOUT` container agent variable, and that
is not the deployment model here.

| Deployment target | Maximum graceful drain | Behaviour on planned replacement |
|---|---|---|
| AKS / EKS / GKE (Helm chart) | 43200s (12h), matched to the runner's own shutdown timeout | Lossless — in-flight tasks complete before the pod exits |
| **ECS Fargate** | **120s, hard limit** | **Lossy for anything still running after 120s — the container is killed and those tasks fail** |

**What this means in practice.** A pipeline still running 120 seconds after a
deployment starts is killed, not drained. Choose ECS for runners whose tasks are
short, or accept that every deployment and scale-in event can fail in-flight
work. Where lossless planned failover is a requirement, use one of the
Kubernetes targets.

## Architecture

```
┌───────────────────────────────────────────┐
│              AWS Account                  │
│  ┌──────────────────────────────────────┐ │
│  │           ECS Cluster                │ │
│  │  ┌─────────────────────────────────┐ │ │
│  │  │         ECS Service             │ │ │
│  │  │  ┌────────────────────────────┐ │ │ │
│  │  │  │      Fargate Tasks         │ │ │ │
│  │  │  │  ┌───────────────────────┐ │ │ │ │
│  │  │  │  │  Matillion Runner     │ │ │ │ │
│  │  │  │  │  (Single Container)   │ │ │ │ │
│  │  │  │  └───────────────────────┘ │ │ │ │
│  │  │  └────────────────────────────┘ │ │ │
│  │  └─────────────────────────────────┘ │ │
│  └──────────────────────────────────────┘ │
│  ┌─────────────────────────────────────┐  │
│  │       AWS Secrets Manager           │  │
│  │      (OAuth Credentials)            │  │
│  └─────────────────────────────────────┘  │
│  ┌─────────────────────────────────────┐  │
│  │          S3 Bucket                  │  │
│  │       (Data Storage)                │  │
│  └─────────────────────────────────────┘  │
│  ┌─────────────────────────────────────┐  │
│  │         CloudWatch                  │  │
│  │    (Logs & Monitoring)              │  │
│  └─────────────────────────────────────┘  │
└───────────────────────────────────────────┘
```

## Prerequisites

- [Terraform 1.0+](https://www.terraform.io/downloads.html)
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate permissions
- AWS account with ECS and Fargate enabled
- VPC with subnets configured for ECS deployment

### Image Delivery & Network Requirements

The Runner image for this deployment is pulled from `public.ecr.aws/matillion/etl-agent`. Your VPC must have network access to that registry — via open egress, a whitelisted egress path, or a private mirror in your deployment region for zero-egress environments. ECR Public's API is hosted only in `us-east-1` / `us-west-2`, so deployments in other regions must reach `us-east-1` over the internet to pull the public image.

See [Network Requirements for Pulling the Runner Image](../../../blogs/runner-image-pull-network-requirements.md) for supported network patterns, the required VPC endpoints for the private-mirror pattern, and configuration steps.

### Required AWS Permissions

```bash
# Configure AWS CLI
aws configure

# Verify permissions
aws sts get-caller-identity
```

The IAM policy for the identity that runs `terraform apply` and `terraform destroy` is in [deploy-policy.json](./deploy-policy.json).

To deploy without `iam:PutRolePolicy`, see [Deploying without iam:PutRolePolicy](#deploying-without-iamputrolepolicy).

Replace the placeholders before you create the policy:

- `<ACCOUNT_ID>`: the 12-digit ID of the AWS account you deploy into.
- `<REGION>`: the region you deploy into, the same value as `region`.
- `<NAME>`: the value of `name`. Every resource this configuration creates is named with the prefix `<NAME>-<salt>`, where `<salt>` is a random 6-character suffix, and the policy scopes its statements to names that start with `<NAME>-`. If you set `secret_name` or `runner_keypair_secret_name`, the value must also start with `<NAME>-`. Use lower case for `name`: the staging bucket name is lower-cased, and the policy's S3 statements match `<NAME>-*` exactly.

A customer managed policy is limited to 6,144 characters, not counting whitespace. The policy is 5,960 characters with the placeholders in place, and replacing them makes it longer. Any `name` of 13 or more characters, including the default `data-insights`, puts it over the limit in every region. Shorter names can also go over in regions with longer codes, such as `ap-southeast-2`. Check the size after replacing the placeholders:

```bash
jq -c . deploy-policy.json | tr -d '\n' | wc -c
```

If the result is over 6,144, split the policy into two customer managed policies and attach both to the same identity. Each half is under the limit for any `name` that the `name` validation allows:

```bash
jq '.Statement |= .[:12]' deploy-policy.json > deploy-policy-1.json
jq '.Statement |= .[12:]' deploy-policy.json > deploy-policy-2.json
```

The policy's EC2 statements require the tag `matillion:deployment-id` with the value `<NAME>` on every resource. This configuration does not set that tag yet (DPC-61601), so set it through `tags`:

```hcl
tags = {
  "matillion:deployment-id" = "<NAME>"
}
```

The policy covers a deployment with the default inputs, except the authentication failure metric filter on the runner task log group. That filter is always created and needs `logs:PutMetricFilter`, `logs:DeleteMetricFilter` and `logs:DescribeMetricFilters`, which the policy does not include. Grant them in a separate policy.

The policy does not cover these optional features. Grant the extra permissions separately if you use them:

- `enable_script_runner = true`: the Cloud Map private DNS namespace and service (`servicediscovery:*` actions and the Route 53 hosted zone actions the namespace needs), and the ingress rule on the script runner security group (`ec2:AuthorizeSecurityGroupIngress`, `ec2:RevokeSecurityGroupIngress`).
- `auth_failure_alarm_actions` set: the CloudWatch alarm (`cloudwatch:PutMetricAlarm`, `cloudwatch:DeleteAlarms`, `cloudwatch:DescribeAlarms`, `cloudwatch:ListTagsForResource`, `cloudwatch:TagResource`, `cloudwatch:UntagResource`).
- `metrics_ingress_cidr_blocks` or `metrics_ingress_security_group_ids` set: the security group ingress rules (`ec2:AuthorizeSecurityGroupIngress`, `ec2:RevokeSecurityGroupIngress`, `ec2:DescribeSecurityGroupRules`).
- `enable_sqs_pipeline_trigger = true`: the SQS queues, DynamoDB table, Lambda function and event source mapping, SNS topic, CloudWatch alarms, the Lambda log group, and the managed policies `AWSLambdaBasicExecutionRole` and `AWSXRayDaemonWriteAccess` attached to the adapter role.
- `script_runner_task_role_policy_arns` set: the policy allows attaching only `SecretsManagerReadWrite`, `CloudWatchFullAccess` and `AmazonECSTaskExecutionRolePolicy`.
- `use_existing_vpc = true`: the policy allows creating subnets and security groups in a VPC, and associating route tables, only when the VPC and its main route table carry the `matillion:deployment-id` tag with the value `<NAME>`.
- An S3 remote state backend (`backend.tf`): the state bucket and lock table need their own permissions.
- Changing or removing tags on an existing deployment: the policy has no `ec2:DeleteTags` or `*:UntagResource` actions.

The policy was audited against this configuration at commit 305ec97. Its resource scopes were updated for later changes (secret names, the Container Insights log group), but it has not been re-verified by a deployment since.

Every resource the deployment creates carries the tag `matillion:deployment-id` with the value of `name`. It is set through the resource tags and the provider default tags. The narrowed deployment policies scope their statements with `aws:RequestTag/matillion:deployment-id` and `aws:ResourceTag/matillion:deployment-id`, using `name` as the value. A `matillion:deployment-id` key in `tags` is overridden by `name`.

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd agent-deployment/runner/aws/ecs
```

### 2. Configure Variables

Create or edit `terraform.tfvars`:

```hcl
# AWS Configuration
region = "us-east-1"
name   = "matillion-runner"

# Matillion Configuration
account_id         = "your-matillion-account-id"
agent_id          = "your-unique-agent-id"
matillion_region  = "us1"
client_id        = "your-oauth-client-id"
client_secret    = "your-oauth-client-secret"

# Networking Configuration
vpc_id             = "vpc-12345678"
subnet_ids         = ["subnet-12345678", "subnet-87654321"]
security_group_ids = ["sg-12345678"]

# Container Configuration
image_url     = "public.ecr.aws/matillion/etl-agent:current"
desired_count = 2
runner_size   = "small"  # small | medium | large | xlarge — see Resource Sizing below
# runner_cpu / runner_memory may still be set as Fargate-valid overrides (see below)

# Optional: Ephemeral Storage
ephemeral_storage_size = 30  # GiB

# Optional: Extension Libraries
extension_library_location = ""
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review deployment plan
terraform plan

# Deploy infrastructure
terraform apply
```

### 4. Verify Deployment

```bash
# Check ECS service status
aws ecs describe-services --cluster <cluster-name> --services <service-name>

# View task logs
aws logs tail /ecs/<name>-<suffix>-task --follow

# Check running tasks
aws ecs list-tasks --cluster <cluster-name> --service-name <service-name>
```

## ⚙️ Configuration Options

### Resource Sizing

Pick a t-shirt size with `runner_size`. Each size maps to a Fargate-valid `cpu`/`memory` pair so you don't have to remember the matrix.

| `runner_size` | vCPU | Memory | `runner_cpu` | `runner_memory` | Notes |
|---|---|---|---|---|---|
| `small` *(default)* | 1 | 4 GiB | 1024 | 4096 | Light/dev workloads, single-pipeline tenants |
| `medium` | 2 | 8 GiB | 2048 | 8192 | Most production deployments |
| `large` | 4 | 16 GiB | 4096 | 16384 | Heavy ELT, large staged datasets |
| `xlarge` | 8 | 32 GiB | 8192 | 32768 | Linux-only on Fargate |

```hcl
# Most deployments
runner_size = "medium"
desired_count = 3
ephemeral_storage_size = 50
```

#### Overrides

If you need a specific Fargate-valid combination outside the t-shirt sizes, set both `runner_cpu` and `runner_memory`. They take precedence over `runner_size`:

```hcl
runner_size   = "small"  # ignored when both overrides are set
runner_cpu    = 2048
runner_memory = 4096
```

The pair must be a valid Fargate combination — see the table in [CPU and Memory Combinations](#cpu-and-memory-combinations) below.

### Disabling Python Script and Bash Script

Set `disable_script_execution = true` to stop the Python Script and Bash Script
components running on the runner tasks. The task definition then sets
`SCRIPT_OOM_PROTECTION_ENABLED=false` and points `MTLN_PYTHON_3_COMMAND` and
`MTLN_BASH_COMMAND` at paths that do not exist, so both components fail at Run
with `Cannot run program "/python-script-disabled-on-this-runner"...`. Script
Pushdown (`enable_script_runner`) still works. To stop scripts running anywhere, also
set `enable_script_runner = false`.

```hcl
disable_script_execution = true
```

Pipelines still pass Validate, the setting is per runner, and it relies on
internal runner settings, so re-check it after runner upgrades. See
[Disabling Python Script and Bash Script](../../../README.md#disabling-python-script-and-bash-script).

### Networking Configuration

#### Public Subnets
```hcl
subnet_ids = ["subnet-public-1", "subnet-public-2"]
# Ensure security groups allow outbound HTTPS (port 443)
```

#### Private Subnets (Recommended)
```hcl
subnet_ids = ["subnet-private-1", "subnet-private-2"]
# Requires NAT Gateway for internet access
```

### Security Group Requirements

```hcl
# Outbound rules required:
# - HTTPS (443) for Matillion API communication
# - Database ports (e.g., 5432 for PostgreSQL) if needed
# - DNS (53) for name resolution
```

The runner tasks always carry a security group created by this deployment, which holds the metrics ingress rules and is the source the script runner security group admits on port 2222. With `use_existing_security_group = false` (the default) that group allows all outbound traffic. With `use_existing_security_group = true` it has no egress rules, and an apply removes any egress rules it already has, so the outbound traffic the runner can send is exactly what the groups in `security_group_ids` allow. Those groups must then allow the destinations listed above and the image registry endpoints described in [Network Requirements for Pulling the Runner Image](../../../blogs/runner-image-pull-network-requirements.md).

The script runner security group (`enable_script_runner = true`) allows all outbound traffic in both cases. There is no input to supply its egress rules. With the script runner enabled and `use_existing_security_group = true`, the groups in `security_group_ids` must also allow TCP 2222 outbound to the script runner tasks.

### CPU and Memory Combinations

| CPU Units | Memory (MB) | vCPU | Use Case |
|-----------|-------------|------|----------|
| 256 | 512-2048 | 0.25 | Light workload |
| 512 | 1024-4096 | 0.5 | Development |
| 1024 | 2048-8192 | 1 | Standard production |
| 2048 | 4096-16384 | 2 | High-performance |
| 4096 | 8192-30720 | 4 | Heavy workload |

## Monitoring and Logging

### CloudWatch Integration

ECS automatically integrates with CloudWatch:

- **Container Logs**: Automatically sent to CloudWatch Logs
- **Metrics**: CPU, Memory, Network utilization
- **Service Events**: Task start/stop, health check results
- **Custom Metrics**: Application-specific metrics

### Log Groups

```bash
# View log groups
aws logs describe-log-groups --log-group-name-prefix "/ecs/"

# Stream logs
aws logs tail "/ecs/<name>-<suffix>-task" --follow
```

### Checking that the runner is connected

`terraform apply` and the ECS deployment status do not detect a wrong client secret. A runner that cannot authenticate keeps its tasks `RUNNING`, the deployment completes, and the runner retries indefinitely. Check the runner log instead:

- `SSE Connection Subscription Started` is logged before the token request and does not mean the runner is connected.
- `Successfully sent in-progress requests to Agent Gateway` appears only on a working runner.
- `Recoverable error caught [[invalid_token_response] An error occurred while attempting to retrieve the OAuth 2.0 Access Token Response: 401 Unauthorized ...` means Keycloak rejected the runner's credentials, for example a wrong client secret. The same line with another status, a timeout or a connection error means the runner could not reach Keycloak.
- `invalid_client` on a line without `Recoverable error caught` is usually a pipeline connector's OAuth failure, not the runner's own sign-in.

To list authentication failures, run this CloudWatch Logs Insights query over `/ecs/<name>-<suffix>-task`:

```bash
aws logs start-query \
  --log-group-name "/ecs/<name>-<suffix>-task" \
  --start-time $(($(date +%s) - 3600)) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message | filter @message like "Recoverable error caught [[invalid_" | sort @timestamp desc'

# Then fetch the results with the queryId returned above
aws logs get-query-results --query-id <query-id>
```

The deployment also counts these log events in the CloudWatch metric `<name>-<suffix>-runner-auth-failures` in the namespace `Matillion/Runner`. To be notified, set `auth_failure_alarm_actions` to a list of ARNs, for example an SNS topic. An alarm is then created that notifies them when the metric's sum is 1 or more in 2 of the last 3 five-minute periods, and again when it returns to `OK`. The alarm also fires while Keycloak is unreachable, and it does not detect a runner that is not running:

```hcl
auth_failure_alarm_actions = ["arn:aws:sns:<region>:<account-id>:<topic>"]
```

### CloudWatch Alarms

```bash
# CPU utilization alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "matillion-runner-high-cpu" \
  --alarm-description "High CPU utilization" \
  --metric-name CPUUtilization \
  --namespace AWS/ECS \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold
```

## Security Configuration

### IAM Roles

The deployment creates two IAM roles:

#### Task Execution Role
- Pull container images from ECR
- Write logs to CloudWatch
- Access secrets from Secrets Manager

#### Task Role
- Application-specific permissions
- S3 bucket access
- Additional AWS service permissions

### Secrets Management

```hcl
# OAuth credentials stored in AWS Secrets Manager
module "secrets_manager" {
  source = "../../../modules/aws/secrets-manager"
  
  client_id     = var.client_id
  client_secret = var.client_secret
}
```

### Deploying without iam:PutRolePolicy

`iam:PutRolePolicy` can be limited by role ARN but not by policy content, so a principal that holds it can write any inline policy on the roles it creates. By default this deployment creates up to five inline policies, so [deploy-policy.json](./deploy-policy.json) includes `iam:PutRolePolicy`.

Each inline policy can be replaced by a policy you create beforehand. When an input below is set, Terraform attaches that policy to the role and does not create the inline policy. You own the content of the policies you supply. Inputs left at `null` keep the inline policy.

| Input | Role | Applies when | Replaces inline policy |
|-------|------|--------------|------------------------|
| `ecs_task_role_policy_arn` | `<name>-<salt>-matillion-ecs-task-role` | always | `matillion_etl_runner_role` |
| `ecs_task_execution_role_policy_arn` | `<name>-<salt>-task-execution-role` | always | `GetETLRunnerSecretValue` |
| `ecs_task_execution_role_keypair_policy_arn` | `<name>-<salt>-task-execution-role` | `enable_script_runner = true` | `GetScriptRunnerKeypairSecretValue` |
| `script_runner_extension_library_policy_arn` | `<name>-<salt>-script-runner-task-role` | `enable_script_runner = true` | `ScriptRunnerExtensionLibraryS3Access` |
| `sqs_adapter_lambda_policy_arn` | `<name>-<salt>-maia-sqs-adapter-role` | `enable_sqs_pipeline_trigger = true` | `<name>-<salt>-maia-sqs-adapter-policy` |

An input whose "Applies when" condition is false is ignored. `script_runner_extension_library_policy_arn` is attached whether or not `script_runner_extension_library_bucket_arn` is set.

#### Creating the policies

Create each policy once per account, or once per deployment where the resources it names differ, with:

```bash
aws iam create-policy --policy-name my-agent-task --policy-document file://task-policy.json
```

**Task role.** Use [`modules/aws/iam/templates/ecs_task_role_policy.json`](../../../modules/aws/iam/templates/ecs_task_role_policy.json) as it is.

**Execution role: OAuth secret and keypair secret.** The execution role reads the OAuth credentials secret and, with `enable_script_runner = true`, the keypair secret. Three options, narrowest first:

1. Exact name. Set `secret_name` and `runner_keypair_secret_name` in `terraform.tfvars`, then grant access to those names only. Secrets Manager appends six random characters to a secret ARN, hence `-??????`. This needs one policy per deployment.

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": "secretsmanager:GetSecretValue",
         "Resource": "arn:aws:secretsmanager:<region>:<account>:secret:<secret_name>-??????"
       }
     ]
   }
   ```

   Use the same document with `<runner_keypair_secret_name>` for the keypair policy.

2. Name prefix. Grant `secretsmanager:GetSecretValue` on `arn:aws:secretsmanager:<region>:<account>:secret:<prefix>*`. Every runner whose execution role has this policy can read every secret under the prefix, including the OAuth credentials of other runners. The default secret names are `<name>-<salt>-oauth-credentials` and `<name>-<salt>-runner-keypair`, and the salt is not known before the first apply, so a prefix that covers the default names must end at `<name>-`.

3. Attribute-based access control (ABAC). Grant `secretsmanager:GetSecretValue` on `*` when the secret's tag matches the role's tag:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": "secretsmanager:GetSecretValue",
         "Resource": "*",
         "Condition": {
           "StringEquals": {
             "secretsmanager:ResourceTag/<key>": "${aws:PrincipalTag/<key>}"
           }
         }
       }
     ]
   }
   ```

   This isolates deployments only when the execution role and the secrets carry a value for `<key>` that is unique to the deployment, and the deploying principal cannot set `<key>` on arbitrary secrets or roles. This deployment tags its roles only with the provider `default_tags` in [`provider.tf`](provider.tf) (`ManagedBy`, `DeploymentType`, `Project`), which are the same for every deployment. With this deployment as it stands, the ABAC policy grants access as broadly as its tag value is shared.

**Script runner extension library.** The same statement as the inline policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ExtensionLibraryS3",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": ["<bucket ARN>", "<bucket ARN>/*"]
    }
  ]
}
```

`script_runner_task_role_policy_arns` can attach the same policy; either works.

**SQS adapter.** The four statements of the module's inline policy, with concrete ARNs. The Lambda dead-letter queue is named `<name>-<salt>-maia-sqs-adapter-lambda-dlq`; the salt is not known before the first apply, so match it with `*`.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadSecret",
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:<region>:<account>:secret:<sqs_adapter_secret_name>-??????"
    },
    {
      "Sid": "ReadProjectMappings",
      "Effect": "Allow",
      "Action": ["dynamodb:GetItem", "dynamodb:Query"],
      "Resource": [
        "arn:aws:dynamodb:<region>:<account>:table/<mapping table name>",
        "arn:aws:dynamodb:<region>:<account>:table/<mapping table name>/index/*"
      ]
    },
    {
      "Sid": "ConsumeSourceQueue",
      "Effect": "Allow",
      "Action": ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"],
      "Resource": "arn:aws:sqs:<region>:<account>:<source queue name>"
    },
    {
      "Sid": "SendToLambdaDlq",
      "Effect": "Allow",
      "Action": "sqs:SendMessage",
      "Resource": "arn:aws:sqs:<region>:<account>:<name>-*-maia-sqs-adapter-lambda-dlq"
    }
  ]
}
```

#### Setting the inputs

```hcl
ecs_task_role_policy_arn                   = "arn:aws:iam::<account>:policy/my-agent-task"
ecs_task_execution_role_policy_arn         = "arn:aws:iam::<account>:policy/my-agent-exec-secret"
ecs_task_execution_role_keypair_policy_arn = "arn:aws:iam::<account>:policy/my-agent-exec-keypair"
script_runner_extension_library_policy_arn = "arn:aws:iam::<account>:policy/my-agent-extlib"
sqs_adapter_lambda_policy_arn              = "arn:aws:iam::<account>:policy/my-agent-sqs-adapter"
```

#### Deployment policy

When every input that applies to the deployment is set, the `IamRoleScoped` statement of [deploy-policy.json](./deploy-policy.json) no longer needs `iam:PutRolePolicy`, `iam:GetRolePolicy` or `iam:DeleteRolePolicy`, and `iam:AttachRolePolicy` and `iam:DetachRolePolicy` can be limited to the supplied policies and the AWS managed policies the deployment attaches. The two IAM statements become:

```json
[
  {
    "Sid": "IamRoleScoped",
    "Effect": "Allow",
    "Action": [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole"
    ],
    "Resource": "arn:aws:iam::<account>:role/<name>-*"
  },
  {
    "Sid": "IamAttachAllowListOnly",
    "Effect": "Allow",
    "Action": ["iam:AttachRolePolicy", "iam:DetachRolePolicy"],
    "Resource": "arn:aws:iam::<account>:role/<name>-*",
    "Condition": {
      "ArnEquals": {
        "iam:PolicyARN": [
          "arn:aws:iam::aws:policy/SecretsManagerReadWrite",
          "arn:aws:iam::aws:policy/CloudWatchFullAccess",
          "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
          "arn:aws:iam::<account>:policy/my-agent-task",
          "arn:aws:iam::<account>:policy/my-agent-exec-secret",
          "arn:aws:iam::<account>:policy/my-agent-exec-keypair",
          "arn:aws:iam::<account>:policy/my-agent-extlib",
          "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
          "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess",
          "arn:aws:iam::<account>:policy/my-agent-sqs-adapter"
        ]
      }
    }
  }
]
```

List only the supplied policies the deployment uses. The last three entries are needed only with `enable_sqs_pipeline_trigger = true`; this root leaves the adapter's X-Ray tracing on, so it attaches `AWSXRayDaemonWriteAccess`.

`iam:ListRolePolicies` stays. The AWS provider (v5.100.0) lists a role's inline policy names every time it reads an `aws_iam_role`, and the read fails if the call is denied. It is a read-only action. `iam:GetRolePolicy` is called only for each inline policy found, so with no inline policies it is not called.

#### Upgrade effect

- Inputs left unset: no change. The task role policy and the execution role secret policy move to `aws_iam_role_policy.ecs_task_role_policy[0]` and `aws_iam_role_policy.ecs_task_execution_role_policy[0]` through `moved` blocks, and the adapter policy (with `enable_sqs_pipeline_trigger = true`) to `aws_iam_role_policy.lambda[0]`, so `terraform plan` shows no changes.
- Setting an input on an existing deployment: the next apply destroys the matching inline policy and creates the attachment. Roles and task definitions are not replaced. Destroying the inline policy needs `iam:DeleteRolePolicy`, so apply this change with the previous deployment policy, then narrow the deployment policy. Terraform does not order the destroy before or after the create, so for a moment the role can lack the grant; apply while the runner is not starting tasks.

#### Upgrading: secrets-manager module path and label

The module directory `modules/aws/secerts-manager` is now
`modules/aws/secrets-manager`, and this root's module label `secert_manager` is
now `secrets_manager`.

- Deployments of this root: a `moved` block in `main.tf` moves
  `module.secert_manager` to `module.secrets_manager` in state. Run
  `terraform init` before the next plan; the plan shows the move and no
  resource changes.
- Configurations that source `modules/aws/secerts-manager` directly must change
  the path to `modules/aws/secrets-manager`.

### Network Security

#### Security Group Best Practices
```hcl
# Minimal outbound rules
resource "aws_security_group_rule" "https_outbound" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = var.security_group_id
}

# Database access (if needed)
resource "aws_security_group_rule" "database_outbound" {
  type              = "egress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/8"]
  security_group_id = var.security_group_id
}
```

## Operations

### Scaling Operations

#### Manual Scaling
```bash
# Update desired count
aws ecs update-service \
  --cluster <cluster-name> \
  --service <service-name> \
  --desired-count 5
```

#### Auto Scaling with Application Auto Scaling
```bash
# Register scalable target
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id service/<cluster-name>/<service-name> \
  --min-capacity 2 \
  --max-capacity 10
```

### Updates and Deployments

#### Application Updates
```bash
# Update task definition with new image
aws ecs update-service \
  --cluster <cluster-name> \
  --service <service-name> \
  --force-new-deployment
```

#### Rolling Updates
ECS automatically performs rolling updates:
- Stops old tasks gradually
- Starts new tasks with updated configuration
- Maintains service availability during updates

#### Upgrading from a version with fixed secret names

Earlier versions named the OAuth secret `matillion-oauth-credentials` and, with `enable_script_runner = true`, the keypair secret `<name>-runner-keypair`. The defaults are now `<name>-<salt>-oauth-credentials` and `<name>-<salt>-runner-keypair`.

If `secret_name` and `runner_keypair_secret_name` are not set, the next `terraform apply` replaces both secrets, both task definitions, and updates the ECS services and the task execution role policies. The order is: old task definitions and secret versions are destroyed, the old secrets are destroyed (the previous version leaves them in Secrets Manager for 30 days), the new secrets and task definitions are created, then the services are updated. A task that starts between the old secret being destroyed and the service update may fail to start, because its task definition still references the deleted secret. Apply while the runner is not scaling or restarting tasks.

The old names cannot be reused for 30 days after the apply. Rolling back to the previous version, or setting `secret_name = "matillion-oauth-credentials"`, fails with `a secret with this name is already scheduled for deletion` until the window ends or the secret is removed with `aws secretsmanager delete-secret --force-delete-without-recovery`.

Deployments that set both names explicitly are updated in place and keep their secrets. The module now sets `recovery_window_in_days = 0` on both secrets, so a later deletion is immediate.

#### Upgrading with `use_existing_security_group = true`

Earlier versions gave the runner security group created by this deployment an egress rule allowing all outbound traffic, including when `use_existing_security_group = true`. AWS applies the union of the rules on every attached group, so that rule overrode any egress restrictions in `security_group_ids`.

With `use_existing_security_group = true`, the next `terraform apply` updates that group in place and removes the allow-all egress rule. The runner's outbound traffic is then limited to what the groups in `security_group_ids` allow. Before applying, check that those groups allow the destinations in [Security Group Requirements](#security-group-requirements), otherwise the runner cannot pull its image or connect to Matillion after the apply. Deployments with `use_existing_security_group = false` are unchanged.

#### Upgrading from a version with an EC2 instance profile

Earlier versions created an IAM instance profile `<name>-<salt>-matillion-ecs-task-instance-profile` for the runner task role, and the task role trusted `ec2.amazonaws.com` as well as `ecs-tasks.amazonaws.com`. The runner runs on Fargate and used neither.

The next `terraform apply` destroys the instance profile and updates the task role trust policy in place to trust only `ecs-tasks.amazonaws.com`. The runner tasks are not replaced. If anything outside this module attached the instance profile to an EC2 instance, detach it before applying.

#### Upgrading from a version with `create_bucket`

The `create_bucket` input is removed. The staging bucket is always created. `create_bucket = false` could not work (the lookup used the generated name suffix and failed at plan), so no working deployment used it. Delete `create_bucket = true` from `terraform.tfvars`; Terraform warns about an undeclared variable if it stays, and errors if it is passed with `-var`. The bucket keeps its state address, so an existing deployment shows no change.

#### Upgrading with `enable_sqs_pipeline_trigger = true`

The SQS adapter resources are now named `<name>-<salt>-maia-sqs-adapter` so that two deployments sharing `name` no longer collide. The next `terraform apply` replaces the adapter Lambda function, its IAM role and policies, log group, SNS alerts topic, CloudWatch alarms and the Lambda dead-letter queue. Messages in the Lambda dead-letter queue and the old log group's history are lost. The source queue and the project-mapping table keep their names and are not replaced. Replacing the IAM role needs `iam:ListInstanceProfilesForRole`, as any role deletion does.

`sqs_adapter_matillion_api_url` now defaults to `https://<matillion_region>.api.matillion.com/dpc/v1` instead of the eu1 URL. A deployment with `matillion_region` other than `eu1` that left the variable unset changes its adapter's `MATILLION_API_URL` on the next apply.

The source queue (`matillion-dpc-requests`) and mapping table (`matillion-project-mappings`) still default to fixed names. A second deployment in the same account and region must set `sqs_adapter_queue_name` and `sqs_adapter_mapping_table_name`, otherwise the table creation fails and the queue creation reuses the first deployment's queue.

#### Upgrading to a version with the authentication failure metric

The next `terraform apply` adds one CloudWatch Logs metric filter on the runner task log group, plus one CloudWatch alarm when `auth_failure_alarm_actions` is set. No existing resource changes. The identity running Terraform needs the permissions listed under [Required AWS Permissions](#required-aws-permissions). See [Checking that the runner is connected](#checking-that-the-runner-is-connected).

#### Upgrading to a version with the `matillion:deployment-id` tag

The next `terraform plan` shows an in-place update to `tags` and `tags_all` on every tagged resource. No resource is replaced.

The identity running the apply needs the tagging actions for those resource types, for example `ec2:CreateTags`, `iam:TagRole`, `iam:TagPolicy`, `kms:TagResource`, `eks:TagResource`, `ecs:TagResource`, `logs:TagResource` and `secretsmanager:TagResource`.

A deployment that set `matillion:deployment-id` in `tags` to a value other than `name` has that value replaced.

### Troubleshooting

#### Service Issues
```bash
# Check service events
aws ecs describe-services \
  --cluster <cluster-name> \
  --services <service-name> \
  --query 'services[0].events[0:5]'

# Check task definition
aws ecs describe-task-definition \
  --task-definition <task-definition-arn>
```

#### Task Startup Issues
```bash
# List tasks
aws ecs list-tasks --cluster <cluster-name>

# Describe specific task
aws ecs describe-tasks \
  --cluster <cluster-name> \
  --tasks <task-arn>

# Check task logs
aws logs get-log-events \
  --log-group-name "/ecs/<name>-<suffix>-task" \
  --log-stream-name "<log-stream-name>"
```

#### Network Connectivity
```bash
# Test VPC connectivity
aws ec2 describe-subnets --subnet-ids subnet-12345678
aws ec2 describe-security-groups --group-ids sg-12345678

# Check NAT Gateway (for private subnets)
aws ec2 describe-nat-gateways
```

## 💰 Cost Optimization

### Pricing Model

ECS Fargate charges for:
- **vCPU**: Per second billing
- **Memory**: Per second billing
- **Storage**: Ephemeral storage above 20GB

### Optimization Strategies

#### Right-sizing
```bash
# Monitor resource usage
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=<service-name> \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Average
```

#### Spot Fargate (Limited Availability)
```hcl
# Use Spot capacity when available
capacity_provider_strategy {
  capacity_provider = "FARGATE_SPOT"
  weight           = 1
}
```

#### Scheduled Scaling
```bash
# Scale down during off-hours
aws application-autoscaling put-scheduled-action \
  --service-namespace ecs \
  --resource-id service/<cluster>/<service> \
  --scalable-dimension ecs:service:DesiredCount \
  --scheduled-action-name scale-down-evening \
  --schedule "cron(0 20 * * ? *)" \
  --scalable-target-action MinCapacity=1,MaxCapacity=1
```

## Limitations

### ECS Fargate Constraints

- **Single Container per Task**: No sidecar support
- **Limited Networking**: Basic VPC networking only
- **Storage**: Ephemeral storage only (max 200GB)
- **Task Size Limits**: Max 16 vCPU / 120 GiB on Linux Fargate (8 vCPU / 60 GiB on Windows). The `xlarge` t-shirt size is Linux-only.

### Metrics

The runner exposes Prometheus metrics at `/actuator/prometheus` on port 8080 (deprecated) and, on runner 12.150.3 or later, at `/metrics` on port 9464. Neither port is reachable from outside the task by default; to scrape them, set `metrics_ingress_security_group_ids` or `metrics_ingress_cidr_blocks` (and optionally `metrics_ingress_ports`), described in [Scraping Runner Metrics](../../../modules/aws/ecs/README.md#scraping-runner-metrics). See [Runner Metrics: Moving to the OpenTelemetry Endpoint](../../../blogs/runner-metrics-migration.md).

## Migration Paths

### From ECS to EKS

If you need Kubernetes-native features like HPA with custom metrics:

```bash
# Deploy EKS version
cd ../eks
terraform init
terraform apply
```

### From EC2 to Fargate

Migration considerations:
- No direct host access
- Task-based scaling instead of instance-based
- Different networking model
- Simplified IAM role structure

## Cleanup

### Destroy Infrastructure

```bash
# Destroy all resources
terraform destroy

# Verify cleanup
aws ecs list-clusters
aws secretsmanager list-secrets
aws s3 ls
aws logs describe-log-groups --log-group-name-prefix /aws/ecs/containerinsights/
```

#### Empty the staging bucket first

This deployment creates an S3 staging bucket without `force_destroy`. If anything has been written to it, `terraform destroy` finishes the other resources and then fails on the bucket with `BucketNotEmpty`, leaving the bucket in state. Empty the bucket before destroying:

```bash
# Find the bucket name in state
terraform state show 'module.runner.aws_s3_bucket.staging_bucket[0]' | grep -E '^\s+bucket\s'

# Delete every object (the bucket is not versioned by this module)
aws s3 rm s3://<bucket-name> --recursive

terraform destroy
```

Objects in the bucket are not recoverable after `aws s3 rm`. If a destroy has already failed with `BucketNotEmpty`, empty the bucket and run `terraform destroy` again.

#### Delete the task definition revisions

`terraform destroy` deregisters the runner and script runner task definitions but does not delete them. The revisions stay listed as `INACTIVE` and keep the Matillion account ID, agent ID and the ARN of the credentials secret in their container definitions. The AWS provider has no option to delete a revision on destroy.

After `terraform destroy`, list and delete them. The families are `<name>-<salt>-task` and `<name>-<salt>-script-runner-task`, where `<salt>` is the six characters after `name` in the ECS cluster name (`terraform state show random_string.salt` shows it before the destroy). If the `modules/aws/ecs` module is used directly and `resource_names` sets `ecs_task_family` or `script_runner_task_family`, use those values as the family names and prefixes instead.

```bash
aws ecs list-task-definitions \
  --status INACTIVE \
  --family-prefix <name>-<salt>- \
  --query 'taskDefinitionArns' --output text

# Up to 10 ARNs per call
aws ecs delete-task-definitions --task-definitions <arn> [<arn> ...]
```

The caller needs `ecs:DeleteTaskDefinitions`. Deleted revisions show `DELETE_IN_PROGRESS` until AWS finishes removing them.

#### Delete the Container Insights log group

After `terraform destroy`, the log group `/aws/ecs/containerinsights/<name>-<salt>-cluster/performance` can exist again. The module removes it on destroy, but AWS can create it once more shortly afterwards, so check immediately and again after about 5 minutes. `<name>-<salt>-cluster` is the ECS cluster name. If you use the `modules/aws/ecs` module directly with a fixed cluster name, follow the [module README](../../../modules/aws/ecs/README.md#container-insights-log-group) instead.

```bash
aws logs describe-log-groups \
  --log-group-name-prefix /aws/ecs/containerinsights/<cluster-name>/performance \
  --query 'logGroups[].[logGroupName,retentionInDays]' --output text

aws logs delete-log-group --log-group-name /aws/ecs/containerinsights/<cluster-name>/performance
```

A recreated group is not in Terraform state and nothing uses it. The salt is regenerated after a full destroy, so a new deployment gets a new cluster name and does not conflict with the leftover group. Importing the group into a new deployment would plan a replacement because the name differs. Delete it instead. Deletion is permanent, so export any log events you need first.

The caller needs `logs:DescribeLogGroups` and `logs:DeleteLogGroup`.

### Manual Cleanup (if needed)

```bash
# Force delete ECS service
aws ecs update-service \
  --cluster <cluster-name> \
  --service <service-name> \
  --desired-count 0

aws ecs delete-service \
  --cluster <cluster-name> \
  --service <service-name>

# Delete CloudWatch logs
aws logs delete-log-group \
  --log-group-name "/ecs/<name>-<suffix>-task"
```

## Performance Considerations

### Resource Allocation

Use `runner_size` (see [Resource Sizing](#resource-sizing)) to pick the cpu/memory pair. The internal map is:

```hcl
{
  small  = { cpu = 1024, memory = 4096  }   # 1 vCPU / 4 GiB
  medium = { cpu = 2048, memory = 8192  }   # 2 vCPU / 8 GiB
  large  = { cpu = 4096, memory = 16384 }   # 4 vCPU / 16 GiB
  xlarge = { cpu = 8192, memory = 32768 }   # 8 vCPU / 32 GiB
}
```

### Network Performance

- Use multiple Availability Zones for better network performance
- Consider placement constraints for data locality
- Optimize security group rules to minimize network overhead

## Support

For ECS-specific issues:

1. **AWS Status**: [AWS Service Health Dashboard](https://status.aws.amazon.com/)
2. **ECS Documentation**: [Amazon ECS Documentation](https://docs.aws.amazon.com/ecs/)
3. **AWS Support**: Create support case for platform issues
4. **GitHub Issues**: Report deployment configuration problems

## Additional Resources

- [Amazon ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [AWS Fargate Pricing](https://aws.amazon.com/fargate/pricing/)
- [ECS Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Comparison with Other Deployment Methods

| Feature | ECS Fargate | EKS | Container Apps |
|---------|-------------|-----|----------------|
| **Management** | Fully Managed | Managed Control Plane | Fully Managed |
| **Scaling** | Manual/Auto Scaling | Manual/HPA/VPA | Auto (0-300) |
| **Networking** | VPC Integration | Advanced (CNI) | Basic |
| **Sidecar Support** | N | Y | N |
| **Cost** | Task-based | Node-based | Pay-per-use |
| **AWS Integration** | Native | Native | N/A |
| **Learning Curve** | Low | High | Low |

Choose ECS Fargate for:
- AWS-native container deployment
- Simple application architectures
- Minimal operational overhead
- Strong AWS service integration
- Cost-effective serverless containers

Choose EKS for:
- Kubernetes ecosystem requirements
- Complex microservices architectures
- Multi-cloud portability
- Advanced networking and storage needs
- Sidecar container patterns (metrics)