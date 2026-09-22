output "lambda_function_arn" {
  description = "ARN of the SQS->DPC adapter Lambda."
  value       = aws_lambda_function.this.arn
}

output "lambda_function_name" {
  description = "Name of the SQS->DPC adapter Lambda."
  value       = aws_lambda_function.this.function_name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role."
  value       = aws_iam_role.lambda.arn
}

output "source_queue_arn" {
  description = "ARN of the source queue being consumed (created or existing)."
  value       = local.queue_arn
}

output "source_queue_url" {
  description = "URL of the source queue being consumed (created or existing)."
  value       = local.queue_url
}

output "source_dlq_arn" {
  description = "ARN of the source dead-letter queue (null when using an existing source queue)."
  value       = local.source_dlq_arn
}

output "lambda_dlq_arn" {
  description = "ARN of the dedicated Lambda async-failure dead-letter queue."
  value       = aws_sqs_queue.lambda_dlq.arn
}

output "project_mapping_table_name" {
  description = "Name of the project-mapping DynamoDB table (created or existing)."
  value       = local.table_name
}

output "alerts_topic_arn" {
  description = "ARN of the SNS alerts topic (null when create_alarms = false)."
  value       = var.create_alarms ? aws_sns_topic.alerts[0].arn : null
}
