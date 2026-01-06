output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.saturation_monitor.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.saturation_monitor.function_name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.saturation_monitor_schedule.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = var.create_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.saturation_monitor_dashboard[0].dashboard_name}" : null
}

output "iam_role_arn" {
  description = "ARN of the Lambda IAM role"
  value       = aws_iam_role.lambda_role.arn
}