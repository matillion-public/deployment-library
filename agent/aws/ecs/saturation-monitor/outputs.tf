output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = module.saturation_monitor.lambda_function_arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = module.saturation_monitor.lambda_function_name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = module.saturation_monitor.eventbridge_rule_arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = module.saturation_monitor.cloudwatch_log_group_name
}

output "dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = module.saturation_monitor.dashboard_url
}

output "iam_role_arn" {
  description = "ARN of the Lambda IAM role"
  value       = module.saturation_monitor.iam_role_arn
}