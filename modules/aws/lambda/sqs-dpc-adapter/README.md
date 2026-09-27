# SQS → DPC pipeline-execution Lambda adapter ("Option A")

Optional add-on that consumes messages from an SQS queue and triggers a Maia
Foundation / DPC pipeline via the DPC pipeline-execution API. This is the
packaged form of the `matillion/poc-dpc-sqs-api` reference implementation.

The Lambda handler ships as an **arm64 container image** (`var.image_uri`); this
module only provisions the surrounding AWS resources.

## What it creates

- Lambda function (container image, arm64) + execution role scoped to exactly
  the queue, table and secret in use.
- A dedicated Lambda async-failure DLQ (always created, so the function has a
  `dead_letter_config` target even when the source queue is bring-your-own).
- Event source mapping (SQS → Lambda) with `ReportBatchItemFailures`.
- CloudWatch log group; optional SNS topic + alarms (DLQ depth, Lambda
  errors/throttles).

## Create-or-bring-your-own

| Resource | Create (default) | Bring your own |
|---|---|---|
| Source SQS queue (+DLQ) | `create_queue = true`, `queue_name = ...` | `create_queue = false`, `existing_queue_arn`, `existing_queue_url` |
| Project-mapping DynamoDB table | `create_mapping_table = true`, `mapping_table_name = ...` | `create_mapping_table = false`, `existing_mapping_table_name`, `existing_mapping_table_arn` |
| OAuth secret | always bring-your-own (`secret_name`) — holds `{client_id, client_secret}` | — |

## Usage

```hcl
module "sqs_dpc_adapter" {
  source      = "../../modules/aws/lambda/sqs-dpc-adapter"
  aws_region  = "eu-west-1"
  image_uri   = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/maia-sqs-adapter:current"
  secret_name = "matillion-dpc"

  # Bring-your-own existing queue (the common migration case):
  create_queue       = false
  existing_queue_arn = "arn:aws:sqs:eu-west-1:123456789012:customer-etl.fifo"
  existing_queue_url = "https://sqs.eu-west-1.amazonaws.com/123456789012/customer-etl.fifo"
}
```

In the `runner/aws/ecs` and `runner/aws/eks` roots this is wired behind
`enable_sqs_pipeline_trigger` (default `false`) with `sqs_adapter_*`
pass-through variables.

## Notes

- The source-queue DLQ redrive uses `maxReceiveCount = 3` (matches the reference
  implementation). Non-retryable errors are deleted (not retried); retryable
  errors flow to the DLQ after the retry budget.
- `checkov` findings for this module are limited to KMS-CMK / 1-year-retention
  items that the sibling `saturation-monitor` module also accepts; no new skip
  posture is introduced.
