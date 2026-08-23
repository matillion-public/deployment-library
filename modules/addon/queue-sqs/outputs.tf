output "trigger_queue_arn" {
  description = "ARN of the trigger queue. Feed to the production PR #118 adapter module (create_queue = false) to compose on top."
  value       = aws_sqs_queue.trigger_queue.arn
}

output "trigger_queue_url" {
  description = "URL of the trigger queue."
  value       = aws_sqs_queue.trigger_queue.url
}

output "trigger_dlq_arn" {
  description = "ARN of the trigger dead-letter queue."
  value       = aws_sqs_queue.trigger_dlq.arn
}

output "trigger_adapter_arn" {
  description = "ARN of the trigger adapter Lambda."
  value       = aws_lambda_function.trigger_adapter.arn
}

output "adapter_role_arn" {
  description = "ARN of the adapter Lambda execution role."
  value       = aws_iam_role.adapter.arn
}
