output "role_arn" {
  description = "ARN of the runner's IAM role. Set this as serviceAccount.roleArn in the Helm values."
  value       = aws_iam_role.runner.arn
}

output "role_name" {
  description = "Name of the runner's IAM role, for additional policy attachments made outside this module."
  value       = aws_iam_role.runner.name
}

output "service_account_name" {
  description = "Kubernetes service account this role trusts. Set this as serviceAccount.name in the Helm values — the two must match or the pod gets no credentials."
  value       = var.service_account_name
}

output "scoped_secret_arns" {
  description = "Secrets this runner can read. Anything absent from this list is not readable by the runner."
  value       = var.secret_arns
}
