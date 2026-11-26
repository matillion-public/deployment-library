output "runner_secret_arn" {
  value = aws_secretsmanager_secret_version.runner_secret_version.arn
}

output "runner_keypair_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the script runner SSH keypair. Empty string when enable_keypair_secret is false."
  value       = var.enable_keypair_secret ? aws_secretsmanager_secret.runner_keypair_secret[0].arn : ""
}

output "runner_secret_name" {
  description = "Name of the Secrets Manager secret containing the runner OAuth credentials."
  value       = aws_secretsmanager_secret.runner_secret.name
}

output "runner_secret_tags" {
  description = "Tags on the runner OAuth credentials secret."
  value       = aws_secretsmanager_secret.runner_secret.tags
}

output "runner_keypair_secret_name" {
  description = "Name of the script runner keypair secret. Empty string when enable_keypair_secret is false."
  value       = var.enable_keypair_secret ? aws_secretsmanager_secret.runner_keypair_secret[0].name : ""
}
