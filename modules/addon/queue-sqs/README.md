# addon/queue-sqs (AWS)

SQS-backed pipeline-trigger add-on. Declares the four composer-contract
resources:

- `trigger_dlq` — `aws_sqs_queue` (14-day retention, SSE).
- `trigger_queue` — `aws_sqs_queue` with a redrive policy to the DLQ.
- `trigger_queue_policy` — `aws_sqs_queue_policy` allowing the account to publish.
- `trigger_adapter` — `aws_lambda_function` (container image) consuming the queue
  via an event source mapping, ordered after the `agent_service`.

Least-privilege consume policy mirrors the composer contract:
`sqs:ReceiveMessage`, `sqs:DeleteMessage`, `sqs:GetQueueAttributes`,
`sqs:GetQueueUrl`.

## Reconciliation with PR #118 (`feat/DPC-52254-sqs-dpc-adapter`)
PR #118 adds [`modules/aws/lambda/sqs-dpc-adapter`](../../aws/lambda) — the
**production** adapter (DynamoDB project-mapping table, OAuth secret wiring,
CloudWatch alarms, tuned event-source mapping). This composer module does **not**
reimplement that logic; it provisions the queue topology plus a thin adapter
Lambda (image reference only) so the composer path resolves today. Once #118
merges, point that module at this module's `trigger_queue_arn` /
`trigger_queue_url` outputs (`create_queue = false`) to compose the richer
adapter on top.

## Key inputs
`deployment_name`, `agent_service_id` *(required)*, `adapter_image_uri`
*(required)*, `queue_name`, redrive/retention tuning, `tags`.

## Outputs
`trigger_queue_arn`, `trigger_queue_url`, `trigger_dlq_arn`,
`trigger_adapter_arn`, `adapter_role_arn`.
