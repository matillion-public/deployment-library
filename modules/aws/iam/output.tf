output "ecs_task_role_arn" {
  value = aws_iam_role.ecs_task_role.arn
}

output "ecs_task_execution_role" {
  value = aws_iam_role.ecs_task_execution_role.arn
}

output "script_runner_task_role_arn" {
  description = "ARN of the script runner task role. Empty string when enable_script_runner is false."
  value       = var.enable_script_runner ? aws_iam_role.script_runner_task_role[0].arn : ""
}
