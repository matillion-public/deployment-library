# AWS resource naming

Builds AWS resource names from your own naming convention, and hands them to the
deployment modules. Nothing here creates infrastructure — it is computation and
validation only.

The modules generate perfectly good names on their own. Reach for this when an
organisation has a naming standard that resource names have to satisfy, which is
usually the point at which a platform team is asked to prove every resource follows
it.

This is the AWS counterpart to `modules/azure/naming`. The mechanism is the same; the
resource table and the character rules are not.

## Quick start

```hcl
module "naming" {
  source = "../../modules/aws/naming"

  tokens = {
    bu        = "ng"
    env       = "p"
    env_short = "pd"     # the short form, for tightly capped types
    region    = "euw1"
    purpose   = "runner"
    instance  = "01"
  }
}

module "deployment" {
  source         = "../../modules/aws/deployment"
  resource_names = module.naming.names
  # ...
}
```

That produces `ng-p-euw1-runner-vpc-01`, `ng-p-euw1-eks-role-01`,
`ng-p-euw1-tfstate-s3-01`, and `/ecs/ng-p-euw1-runner-log-01`.

## How a name is built

A name is a format string with the tokens substituted in:

| Token | From |
|---|---|
| `{bu}` | `tokens.bu` |
| `{env}` | `tokens.env` |
| `{envs}` | `tokens.env_short` |
| `{region}` | `tokens.region` |
| `{purpose}` | the spec's own `purpose`, else `tokens.purpose` |
| `{type}` | the spec's `type` — the resource abbreviation |
| `{instance}` | `tokens.instance` |

The default format is `{bu}-{env}-{region}-{purpose}-{type}-{instance}`. Any token
left empty drops out without leaving a doubled or trailing separator behind, so a
convention with no purpose segment still produces a clean name.

A spec may also carry a `prefix` or `suffix`, applied after substitution and counted
against `max_length`.

Names are **not truncated to fit**. Silently cutting a name to `max_length` drops the
trailing `{type}` and `{instance}` segments, so two deployments differing only by
instance number collapse onto the same name — and for a globally unique type like an
S3 bucket the second then fails at apply, in a separate state where the uniqueness
check cannot see it. A name that does not fit is a convention error and fails the
plan.

## Resource keys

71 keys, one per resource the modules name, grouped by the module that consumes them:

| Module | Keys |
|---|---|
| `aws/deployment` | `vpc`, `internet_gateway`, `public_route_table`, `private_route_table`, `public_subnet`, `private_subnet`, `nat_eip`, `nat_gateway`, `k8s_security_group` |
| `aws/ecs` | `staging_bucket`, `ecs_security_group`, `ecs_cluster`, `ecs_task_family`, `ecs_service`, `service_discovery_namespace`, `ecs_task_log_group`, `script_runner_security_group`, `script_runner_log_group`, `script_runner_task_family`, `script_runner_service` |
| `aws/eks` | `eks_cluster`, `eks_role`, `fargate_pod_execution_role`, `service_account_role`, `dpc_policy`, `fargate_profile`, `log_bucket`, `eks_secret` |
| `aws/iam` | `ecs_task_role`, `ecs_task_execution_role`, `script_runner_task_role`, `ecs_task_instance_profile`, `ecs_task_role_policy`, `ecs_task_execution_secret_policy`, `ecs_task_execution_keypair_policy`, `script_runner_s3_policy` |
| `aws/runner-identity` | `runner_role`, `runner_secrets_policy`, `runner_s3_policy` |
| `aws/state-management` | `state_bucket`, `state_lock_table` |
| `aws/lambda/saturation-monitor` | `saturation_function`, `saturation_lambda_role`, `saturation_lambda_policy`, `saturation_lambda_sg`, `saturation_schedule_rule`, `saturation_dashboard`, `saturation_alarm_task`, `saturation_alarm_queue`, `saturation_alarm_errors`, `vpc_endpoints_security_group`, `vpc_endpoint_ecs`, `vpc_endpoint_cloudwatch`, `vpc_endpoint_logs` |
| `aws/lambda/sqs-dpc-adapter` | `adapter_function`, `adapter_role`, `adapter_policy`, `adapter_source_queue`, `adapter_source_dlq`, `adapter_lambda_dlq`, `adapter_mapping_table`, `adapter_alerts_topic`, `adapter_alarm_dlq`, `adapter_alarm_errors`, `adapter_alarm_throttles` |
| `addon/queue-sqs` | `trigger_queue`, `trigger_dlq`, `trigger_adapter_dlq`, `trigger_adapter_function`, `trigger_adapter_role`, `trigger_adapter_policy` |

### Why some keys carry their own purpose

Conventions abbreviate the resource type, so every IAM role is `role` and every
policy is `policy`. There are nine roles and eleven policies across these modules —
without something to tell them apart they would all generate the same name and
collide on apply. Each therefore carries a distinguishing `purpose`, overridable per
key in `resource_specs`.

The `addon/queue-sqs` keys and the `aws/lambda/sqs-dpc-adapter` keys are alternative
implementations of the same queue topology rather than companions, but both sets live
in one map, so they carry distinct purposes to keep the uniqueness check meaningful.

## Character sets are per resource type

This is where AWS differs most from Azure. Azure gets away with two name forms
because its resource types are broadly consistent. AWS resource types are not, so
each spec names the character set it has to satisfy:

| `charset` | Pattern | Used by |
|---|---|---|
| `dash` | letters, digits, `-` | the default — most resources |
| `underscore` | letters, digits, `-` `_` | ECS task families, EKS clusters, dashboards |
| `iam` | letters, digits, `+=,.@_-` | roles, policies, instance profiles |
| `lowerdot` | lowercase, `.` `-`, must start and end alphanumeric | S3 buckets, private DNS namespaces |
| `ddb` | letters, digits, `_` `.` `-` | DynamoDB tables — accepts uppercase, unlike S3 |
| `path` | leading `/`, then letters, digits, `.` `_` `/` `-` | CloudWatch log groups |
| `sqs` | letters, digits, `-` `_`, optional `.fifo` | SQS queues |
| `secret` | letters, digits, `/_+=.@-` | Secrets Manager secrets |

A convention that is valid for one resource type is not automatically valid for
another. `ng.p.euw1.eks.role.01` is a legal IAM role name and an illegal ECS cluster
name; both are checked.

### FIFO queues

A FIFO queue's name must end `.fifo`. The modules append it themselves for the queue
they create, so a convention does not have to remember it. To have the naming module
generate it — for a queue whose name you pass elsewhere — set the suffix explicitly:

```hcl
resource_specs = {
  adapter_source_queue = { type = "sqs", max_length = 80, charset = "sqs", suffix = ".fifo" }
}
```

## Names AWS does not let you choose

**Lambda log groups have no key.** Lambda writes to `/aws/lambda/<function-name>`,
which is not a free choice. The two Lambda modules derive the log group name from
`saturation_function` and `adapter_function` respectively, so renaming a function
cannot leave its log group orphaned and the function unable to log. The ECS log
groups are genuinely nameable, which is why they do have keys.

**Security group names cannot start with `sg-`**, which AWS reserves for the
generated group id. This is reachable for real — a business unit abbreviated `sg`
produces exactly that — so it fails the plan rather than the apply.

## Name tags are not always identities

Most of `modules/aws/deployment` — the VPC, subnets, internet gateway, route tables,
EIP and NAT gateway — has no `name` argument at all. AWS names those only through a
`Name` tag. Two consequences:

- Renaming them is **free**: a tag change updates in place, with no destroy and
  recreate. This is unlike Azure, where nearly every rename replaces the resource.
- The limit in the table for those keys is the 256-character tag ceiling, not a
  resource-name limit, so they are effectively unconstrained.

Where a resource has both, the `Name` tag follows the identity, so the tag and the
resource name always agree.

The per-AZ resources — subnets, EIPs, NAT gateways, private route tables — take their
base name from the map and keep the existing `-<index>` suffix, since one template
cannot name N of them.

### Overriding part of a spec

`resource_specs` is merged into the built-in table **per attribute**, so naming one
field leaves the rest alone:

```hcl
resource_specs = {
  eks_role             = { type = "iamrole" }   # keeps the 64-char limit and iam charset
  adapter_source_queue = { suffix = ".fifo" }   # keeps type, charset, purpose, limit
}
```

A key the table does not already contain needs `type`, `charset` and `max_length` set
explicitly, since there is no built-in spec to inherit from.

## When the convention does not fit

Not every standard is expressible as a template — some are irregular, and an existing
platform may already have names that cannot change. Set them outright:

```hcl
overrides = { eks_cluster = "an-existing-name-we-cannot-change" }
```

Overrides win over anything generated, and are still validated.

## Container and service-discovery names are excluded

Two things inside `modules/aws/ecs` are deliberately not covered:

- **Container definition names.** These are internal to a task definition rather than
  AWS resources with ARNs, and a naming standard covers the account inventory.
- **The `script-runner` service-discovery name.** ECS Service Connect turns it into
  the DNS name the agent resolves to reach the runner. Renaming it breaks that
  resolution at runtime, well after a clean apply — the same class of failure as the
  Kubernetes names below.

## Validation

Names are checked at **plan** time, not apply. Four things are enforced:

- **Length**, against the AWS limit for that resource type, measured on the finished
  name including any prefix and suffix. IAM roles cap at 64 characters and are usually
  the first thing a long convention breaks. Over-length fails the plan rather than
  being truncated.
- **Character set**, per resource type, as above.
- **Reserved prefixes** — the `sg-` case.
- **Uniqueness.** Two keys resolving to the same name fails the plan.

Each failure names the offending key, its value and the rule it broke.

## This applies to AWS resources only

Kubernetes names — the namespace, the ServiceAccounts — are deliberately **not**
covered, and should not be renamed to match an AWS convention. The IRSA trust policy
references the service account exactly; if it no longer matches what the Helm chart
deploys, `AssumeRoleWithWebIdentity` fails and the runner cannot reach AWS APIs. The
symptom is an authentication error at runtime, well after a clean apply.

## Compatibility

`resource_names` defaults to an empty map, and every module falls back to the name it
generates today. An existing deployment that does not set it plans clean, with no
changes.

Adding naming to a **deployed** platform renames live resources. For the tag-only
networking resources that is an in-place update; for everything else — clusters,
roles, buckets, queues — it means destroy and recreate. Check the plan.

## Tests

```sh
cd modules/aws/naming && terraform test
```

18 tests, covering the dashed convention, path-prefixed log groups, lowercase S3
buckets, empty tokens collapsing without dangling separators, overrides winning,
custom formats and abbreviations, the 64-character IAM ceiling, role collision
detection, the `.fifo` suffix and a suffix that pushes a name over its limit, the
reserved `sg-` prefix, per-charset acceptance and rejection of the same name, an
over-length generated name failing the plan, a partial `resource_specs` override
keeping the built-in attributes, and a per-key underscore form staying
underscore-separated.
