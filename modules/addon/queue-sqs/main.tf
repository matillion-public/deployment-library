# modules/addon/queue-sqs  (AWS)
#
# SQS-backed pipeline-trigger add-on. Declares the four composer-contract
# resources: trigger_dlq, trigger_queue (depends on the DLQ via redrive),
# trigger_queue_policy, and trigger_adapter (Lambda, depends on the queue and
# the agent_service).
#
# RECONCILIATION WITH PR #118 (feat/DPC-52254-sqs-dpc-adapter):
# PR #118 adds modules/aws/lambda/sqs-dpc-adapter — the production adapter with
# the DynamoDB project-mapping table, OAuth secret wiring, CloudWatch alarms and
# event-source mapping. This composer module intentionally does NOT reimplement
# that logic: it provisions the queue topology + a thin adapter Lambda (image
# reference only) so the composer path resolves today. Once #118 merges, the
# richer module can be composed on top by pointing it at this module's
# `trigger_queue_arn`/`trigger_queue_url` outputs (create_queue = false). The
# least-privilege consume policy here mirrors that module's ConsumeSourceQueue
# statement.

data "aws_caller_identity" "this" {}

locals {
  base_name = var.queue_name != "" ? var.queue_name : "${var.deployment_name}-triggers"
  # Reference agent_service_id to order the adapter after the agent service.
  agent_ref = var.agent_service_id
}

resource "aws_sqs_queue" "trigger_dlq" {
  name                      = lookup(var.resource_names, "trigger_dlq", "${local.base_name}-dlq")
  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true
  tags                      = var.tags
}

resource "aws_sqs_queue" "trigger_queue" {
  name                       = lookup(var.resource_names, "trigger_queue", local.base_name)
  visibility_timeout_seconds = var.visibility_timeout
  message_retention_seconds  = var.message_retention_seconds
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.trigger_dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = var.tags
}

# Allow the agent's account to publish trigger messages onto the queue.
data "aws_iam_policy_document" "trigger_queue_policy" {
  statement {
    sid     = "AllowAccountSend"
    effect  = "Allow"
    actions = ["sqs:SendMessage"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.this.account_id}:root"]
    }
    resources = [aws_sqs_queue.trigger_queue.arn]
  }
}

resource "aws_sqs_queue_policy" "trigger_queue_policy" {
  queue_url = aws_sqs_queue.trigger_queue.id
  policy    = data.aws_iam_policy_document.trigger_queue_policy.json
}

# --------------------------------------------------------------------------- #
# trigger_adapter: thin consumer Lambda. Least-privilege SQS consume policy    #
# mirrors the composer contract (Receive/Delete/GetQueueAttributes/GetQueueUrl).#
# --------------------------------------------------------------------------- #
data "aws_iam_policy_document" "adapter_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "adapter" {
  name               = lookup(var.resource_names, "trigger_adapter_role", "${local.base_name}-adapter-role")
  assume_role_policy = data.aws_iam_policy_document.adapter_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "adapter_basic" {
  role       = aws_iam_role.adapter.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "adapter_consume" {
  statement {
    sid    = "ConsumeTriggerQueue"
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]
    resources = [aws_sqs_queue.trigger_queue.arn]
  }
}

resource "aws_iam_role_policy" "adapter_consume" {
  name   = lookup(var.resource_names, "trigger_adapter_policy", "${local.base_name}-adapter-consume")
  role   = aws_iam_role.adapter.id
  policy = data.aws_iam_policy_document.adapter_consume.json
}

# Dedicated async dead-letter queue for the Lambda itself.
resource "aws_sqs_queue" "adapter_dlq" {
  name                    = lookup(var.resource_names, "trigger_adapter_dlq", "${local.base_name}-adapter-dlq")
  sqs_managed_sse_enabled = true
  tags                    = var.tags
}

resource "aws_lambda_function" "trigger_adapter" {
  # checkov:skip=CKV_AWS_272:Code signing not used for the container-image adapter (image is signed at the registry).
  # checkov:skip=CKV_AWS_117:Adapter reaches the public DPC API; VPC attachment is opt-in via the production PR #118 module.
  function_name                  = lookup(var.resource_names, "trigger_adapter_function", "${local.base_name}-adapter")
  role                           = aws_iam_role.adapter.arn
  package_type                   = "Image"
  image_uri                      = var.adapter_image_uri
  timeout                        = 60
  memory_size                    = 512
  reserved_concurrent_executions = var.adapter_reserved_concurrency

  # Reference the agent service so the adapter is created after it.
  environment {
    variables = {
      MATILLION_AGENT_SERVICE = local.agent_ref
      MATILLION_QUEUE_URL     = aws_sqs_queue.trigger_queue.url
    }
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.adapter_dlq.arn
  }

  tracing_config {
    mode = "Active"
  }

  tags = var.tags
}

resource "aws_lambda_event_source_mapping" "trigger" {
  event_source_arn = aws_sqs_queue.trigger_queue.arn
  function_name    = aws_lambda_function.trigger_adapter.arn
  batch_size       = 10
}
