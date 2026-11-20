output "lambda_function_arn" {
  description = "ARN of the MSK->Maia Foundation adapter Lambda."
  value       = aws_lambda_function.this.arn
}

output "lambda_function_name" {
  description = "Name of the MSK->Maia Foundation adapter Lambda."
  value       = aws_lambda_function.this.function_name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role."
  value       = aws_iam_role.lambda.arn
}

output "event_source_mapping_uuids" {
  description = "Event source mapping UUID per topic."
  value       = { for topic, m in aws_lambda_event_source_mapping.msk : topic => m.uuid }
}

output "consumer_group_ids" {
  description = "Kafka consumer group ID per topic, for granting the SCRAM user its ACLs."
  value       = { for topic, m in aws_lambda_event_source_mapping.msk : topic => m.amazon_managed_kafka_event_source_config[0].consumer_group_id }
}

output "project_mapping_table_name" {
  description = "Name of the project-mapping DynamoDB table (created or existing)."
  value       = local.table_name
}

output "alerts_topic_arn" {
  description = "ARN of the SNS alerts topic (null when create_alarms = false)."
  value       = var.create_alarms ? aws_sns_topic.alerts[0].arn : null
}
