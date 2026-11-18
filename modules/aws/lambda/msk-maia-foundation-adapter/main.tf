###############################################################################
# Amazon MSK -> Maia Foundation pipeline-execution Lambda adapter - resources
###############################################################################

data "aws_secretsmanager_secret" "maia_foundation" {
  name = var.secret_name
}

locals {
  function_name = lookup(var.resource_names, "msk_adapter_function", var.name_prefix)
  table_name    = var.create_mapping_table ? aws_dynamodb_table.mapping[0].name : var.existing_mapping_table_name
  table_arn     = var.create_mapping_table ? aws_dynamodb_table.mapping[0].arn : var.existing_mapping_table_arn

  # One failure-topic alarm per topic. The topic distinguishes the alarms, so when
  # the name would exceed CloudWatch's 255 characters the prefix is truncated, never
  # the topic; truncating the end instead would collide two long topics that share a
  # prefix and silently overwrite one alarm. Topic names (<=249) always fit whole.
  failure_alarm_prefix = lookup(var.resource_names, "msk_adapter_alarm_failure_topic", "${var.name_prefix}-failure-topic")

  tags = merge({
    Component = "msk-maia-foundation-adapter"
    ManagedBy = "Terraform"
  }, var.tags)
}

resource "aws_dynamodb_table" "mapping" {
  count = var.create_mapping_table ? 1 : 0

  name         = lookup(var.resource_names, "msk_adapter_mapping_table", var.mapping_table_name)
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
  name               = lookup(var.resource_names, "msk_adapter_role", "${var.name_prefix}-role")
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Cluster discovery and the network interfaces the pollers open in the cluster's VPC.
resource "aws_iam_role_policy_attachment" "msk" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaMSKExecutionRole"
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
    resources = [data.aws_secretsmanager_secret.maia_foundation.arn]
  }

  statement {
    sid       = "ReadProjectMappings"
    actions   = ["dynamodb:GetItem", "dynamodb:Query"]
    resources = [local.table_arn, "${local.table_arn}/index/*"]
  }

  # Not in AWSLambdaMSKExecutionRole; CreateEventSourceMapping fails without it.
  statement {
    sid       = "ListScramSecrets"
    actions   = ["kafka:ListScramSecrets"]
    resources = [var.cluster_arn]
  }

  statement {
    sid       = "ReadScramSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.scram_secret_arn]
  }

  statement {
    sid       = "DecryptScramSecret"
    actions   = ["kms:Decrypt"]
    resources = [var.scram_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = lookup(var.resource_names, "msk_adapter_policy", "${var.name_prefix}-policy")
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

resource "aws_lambda_function" "this" {
  #checkov:skip=CKV_AWS_116:An MSK mapping invokes the function synchronously, so there are no asynchronous failures for a DLQ; failed records go to the Kafka failure topic.
  #checkov:skip=CKV_AWS_117:Adapter reaches DynamoDB/Secrets Manager and the public Maia Foundation API over public AWS endpoints; the MSK pollers, not the function, run in the cluster's VPC.
  #checkov:skip=CKV_AWS_272:Code signing does not apply to container-image (PackageType=Image) functions.
  function_name = local.function_name
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

  environment {
    variables = {
      MATILLION_AWS_REGION            = var.aws_region
      MATILLION_AWS_EVENT_SOURCE      = "msk"
      MATILLION_MSK_TOPIC_ROUTES      = jsonencode(var.topic_routes)
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

# One mapping per topic, since a Kafka mapping reads exactly one. Provisioned mode
# is what allows partial batch responses, a retry limit and the failure topic;
# without it a failing record is retried until it expires.
resource "aws_lambda_event_source_mapping" "msk" {
  for_each = toset(var.topics)

  event_source_arn  = var.cluster_arn
  function_name     = aws_lambda_function.this.arn
  topics            = [each.value]
  starting_position = var.starting_position
  batch_size        = var.batch_size

  function_response_types = ["ReportBatchItemFailures"]
  maximum_retry_attempts  = var.maximum_retry_attempts

  # A consumer group ID must be unique across Kafka event sources.
  amazon_managed_kafka_event_source_config {
    consumer_group_id = "${local.function_name}-${each.value}"
  }

  source_access_configuration {
    type = "SASL_SCRAM_512_AUTH"
    uri  = var.scram_secret_arn
  }

  # Every topic's mapping is in one poller group, so they share event poller
  # units instead of each topic being billed for its own.
  provisioned_poller_config {
    minimum_pollers   = var.minimum_pollers
    maximum_pollers   = var.maximum_pollers
    poller_group_name = local.function_name
  }

  destination_config {
    on_failure {
      destination_arn = "kafka://${var.failure_topic}"
    }
  }

  # Counts records delivered to the failure topic and records dropped because they
  # could not be written there; the failure_topic alarms read both.
  metrics_config {
    metrics = ["EventCount"]
  }

  # Lambda checks the role's cluster and secret access when the mapping is
  # created, so the grants have to exist first.
  depends_on = [aws_iam_role_policy.lambda, aws_iam_role_policy_attachment.msk]
}

resource "aws_sns_topic" "alerts" {
  count             = var.create_alarms ? 1 : 0
  name              = lookup(var.resource_names, "msk_adapter_alerts_topic", "${var.name_prefix}-alerts")
  kms_master_key_id = "alias/aws/sns"
  tags              = local.tags
}

# A record that fails is reported as a partial batch failure rather than raised, so
# the errors alarm never sees it. This alarm fires when one reaches the failure
# topic, or is dropped because it could not be written there.
resource "aws_cloudwatch_metric_alarm" "failure_topic" {
  for_each = var.create_alarms ? aws_lambda_event_source_mapping.msk : {}

  alarm_name          = "${substr(local.failure_alarm_prefix, 0, max(1, 254 - length(each.key)))}-${each.key}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_description   = "Records from ${each.key} failed to trigger a pipeline and were sent to ${var.failure_topic}, or could not be written there."
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]
  tags                = local.tags

  metric_query {
    id          = "failed"
    expression  = "FILL(delivered, 0) + FILL(dropped, 0)"
    label       = "Records that failed to trigger a pipeline"
    return_data = true
  }

  metric_query {
    id = "delivered"
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "OnFailureDestinationDeliveredEventCount"
      dimensions  = { EventSourceMappingUUID = each.value.uuid }
      period      = 300
      stat        = "Sum"
    }
  }

  metric_query {
    id = "dropped"
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "DroppedEventCount"
      dimensions  = { EventSourceMappingUUID = each.value.uuid }
      period      = 300
      stat        = "Sum"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.create_alarms ? 1 : 0

  alarm_name          = lookup(var.resource_names, "msk_adapter_alarm_errors", "${var.name_prefix}-lambda-errors")
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = var.alarm_lambda_error_threshold
  alarm_description   = "MSK->Maia Foundation adapter Lambda is reporting errors."
  dimensions          = { FunctionName = aws_lambda_function.this.function_name }
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]
  tags                = local.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  count = var.create_alarms ? 1 : 0

  alarm_name          = lookup(var.resource_names, "msk_adapter_alarm_throttles", "${var.name_prefix}-lambda-throttles")
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "MSK->Maia Foundation adapter Lambda is being throttled."
  dimensions          = { FunctionName = aws_lambda_function.this.function_name }
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]
  tags                = local.tags
}
