output "runner_secret_arn" {
  value = aws_secretsmanager_secret_version.runner_secret_version.arn
}

output "runner_keypair_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the script runner SSH keypair. Empty string when enable_keypair_secret is false."
  value       = var.enable_keypair_secret ? aws_secretsmanager_secret.runner_keypair_secret[0].arn : ""
}
