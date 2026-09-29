###############################################################################
# SQS -> DPC pipeline-execution Lambda adapter ("Option A") - resources
###############################################################################

data "aws_secretsmanager_secret" "dpc" {
  name = var.secret_name
}

locals {
  # The .fifo normalisation is applied to whichever name wins, so a convention
  # does not have to remember the suffix for the queue this module creates.
  source_queue_base = lookup(var.resource_names, "adapter_source_queue", var.queue_name)
  source_queue_name = var.fifo_queue ? (endswith(local.source_queue_base, ".fifo") ? local.source_queue_base : "${local.source_queue_base}.fifo") : local.source_queue_base

  queue_arn      = var.create_queue ? aws_sqs_queue.source[0].arn : var.existing_queue_arn
  queue_url      = var.create_queue ? aws_sqs_queue.source[0].url : var.existing_queue_url
  source_dlq_arn = var.create_queue ? aws_sqs_queue.source_dlq[0].arn : null


  # Lambda rejects a batching window on a FIFO source: CreateEventSourceMapping
  # returns "Batching window is not supported for FIFO queues". With a BYO queue
  # the ARN suffix is the only signal available, since fifo_queue only describes
  # the queue this module creates.
  source_is_fifo = var.create_queue ? var.fifo_queue : endswith(var.existing_queue_arn, ".fifo")
  table_name     = var.create_mapping_table ? aws_dynamodb_table.mapping[0].name : var.existing_mapping_table_name
  table_arn      = var.create_mapping_table ? aws_dynamodb_table.mapping[0].arn : var.existing_mapping_table_arn

  tags = merge({
    Component = "sqs-dpc-adapter"
    ManagedBy = "Terraform"
  }, var.tags)
}

# ---------------------------------------------------------------------------
# Source queue (created only when create_queue = true).
# ---------------------------------------------------------------------------
resource "aws_sqs_queue" "source_dlq" {
  count = var.create_queue ? 1 : 0

  name                        = lookup(var.resource_names, "adapter_source_dlq", var.fifo_queue ? "${trimsuffix(local.source_queue_name, ".fifo")}-dlq.fifo" : "${local.source_queue_name}-dlq")
  fifo_queue                  = var.fifo_queue
  content_based_deduplication = var.fifo_queue ? true : null
  message_retention_seconds   = 1209600 # 14 days
  sqs_managed_sse_enabled     = true
  tags                        = local.tags
}

resource "aws_sqs_queue" "source" {
  count = var.create_queue ? 1 : 0

  name                        = local.source_queue_name
  fifo_queue                  = var.fifo_queue
  content_based_deduplication = var.fifo_queue ? true : null
  deduplication_scope         = var.fifo_queue ? "messageGroup" : null
  fifo_throughput_limit       = var.fifo_queue ? "perMessageGroupId" : null
  visibility_timeout_seconds  = var.visibility_timeout
  message_retention_seconds   = var.message_retention_seconds
  sqs_managed_sse_enabled     = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.source_dlq[0].arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = local.tags
}

resource "aws_sqs_queue_redrive_allow_policy" "source_dlq" {
  count = var.create_queue ? 1 : 0

  queue_url = aws_sqs_queue.source_dlq[0].id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.source[0].arn]
  })
}

# Dedicated DLQ for asynchronous Lambda invocation failures (always created so
# the function has a dead_letter_config target even when the source queue is BYO).
resource "aws_sqs_queue" "lambda_dlq" {
  name                      = lookup(var.resource_names, "adapter_lambda_dlq", "${var.name_prefix}-lambda-dlq")
  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true
  tags                      = local.tags
}

# ---------------------------------------------------------------------------
# Project-mapping table (created only when create_mapping_table = true).
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "mapping" {
  count = var.create_mapping_table ? 1 : 0

  name         = lookup(var.resource_names, "adapter_mapping_table", var.mapping_table_name)
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }
  attribute {
    name = "SK"
    type = "S"
  }
  attribute {
    name = "project_id"
    type = "S"
  }

  global_secondary_index {
    name            = "project-id-index"
    hash_key        = "project_id"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# IAM role for the Lambda (scoped to the resources actually in use).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = lookup(var.resource_names, "adapter_role", "${var.name_prefix}-role")
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "xray" {
  count      = var.enable_xray_tracing ? 1 : 0
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

data "aws_iam_policy_document" "lambda" {
  statement {
    sid       = "ReadSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [data.aws_secretsmanager_secret.dpc.arn]
  }

  statement {
    sid       = "ReadProjectMappings"
    actions   = ["dynamodb:GetItem", "dynamodb:Query"]
    resources = [local.table_arn, "${local.table_arn}/index/*"]
  }

  statement {
    sid       = "ConsumeSourceQueue"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [local.queue_arn]
  }

  statement {
    sid       = "SendToLambdaDlq"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.lambda_dlq.arn]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = lookup(var.resource_names, "adapter_policy", "${var.name_prefix}-policy")
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

# ---------------------------------------------------------------------------
# Lambda function (container image) + log group + event source mapping.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${lookup(var.resource_names, "adapter_function", var.name_prefix)}"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

resource "aws_lambda_function" "this" {
  #checkov:skip=CKV_AWS_117:Adapter reaches SQS/DynamoDB/Secrets Manager and the public DPC API over public AWS endpoints; VPC attachment is not required.
  #checkov:skip=CKV_AWS_272:Code signing does not apply to container-image (PackageType=Image) functions.
  function_name = lookup(var.resource_names, "adapter_function", var.name_prefix)
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = var.image_uri
  architectures = ["arm64"]
  memory_size   = var.memory_size
  timeout       = var.timeout

  reserved_concurrent_executions = var.reserved_concurrency

  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  environment {
    variables = {
      MATILLION_AWS_REGION            = var.aws_region
      MATILLION_SECRET_NAME           = var.secret_name
      MATILLION_PROJECT_MAPPING_TABLE = local.table_name
      MATILLION_API_URL               = var.matillion_api_url
      MATILLION_TOKEN_URL             = var.matillion_token_url
      MATILLION_LOG_LEVEL             = var.log_level
      MATILLION_ENABLE_XRAY_TRACING   = tostring(var.enable_xray_tracing)
      POWERTOOLS_SERVICE_NAME         = var.name_prefix
      POWERTOOLS_METRICS_NAMESPACE    = "MatillionDPC"
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda,
    aws_cloudwatch_log_group.lambda,
  ]

  tags = local.tags
}

resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn                   = local.queue_arn
  function_name                      = aws_lambda_function.this.arn
  batch_size                         = var.batch_size
  maximum_batching_window_in_seconds = local.source_is_fifo ? null : var.batching_window_seconds
  function_response_types            = ["ReportBatchItemFailures"]
}

# ---------------------------------------------------------------------------
# Optional observability.
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  count             = var.create_alarms ? 1 : 0
  name              = lookup(var.resource_names, "adapter_alerts_topic", "${var.name_prefix}-alerts")
  kms_master_key_id = "alias/aws/sns"
  tags              = local.tags
}

resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  count = var.create_alarms && var.create_queue ? 1 : 0

  alarm_name          = lookup(var.resource_names, "adapter_alarm_dlq", "${var.name_prefix}-dlq-messages")
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = var.alarm_dlq_message_threshold
  alarm_description   = "Messages have landed in the SQS->DPC adapter dead-letter queue."
  dimensions          = { QueueName = aws_sqs_queue.source_dlq[0].name }
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]
  tags                = local.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.create_alarms ? 1 : 0

  alarm_name          = lookup(var.resource_names, "adapter_alarm_errors", "${var.name_prefix}-lambda-errors")
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = var.alarm_lambda_error_threshold
  alarm_description   = "SQS->DPC adapter Lambda is reporting errors."
  dimensions          = { FunctionName = aws_lambda_function.this.function_name }
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]
  tags                = local.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  count = var.create_alarms ? 1 : 0

  alarm_name          = lookup(var.resource_names, "adapter_alarm_throttles", "${var.name_prefix}-lambda-throttles")
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "SQS->DPC adapter Lambda is being throttled."
  dimensions          = { FunctionName = aws_lambda_function.this.function_name }
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]
  tags                = local.tags
}
