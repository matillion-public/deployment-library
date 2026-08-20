output "account_id" {
  description = "Matillion account ID."
  value       = var.account_id
}

output "region" {
  description = "Matillion control-plane region."
  value       = var.region
}

output "agent_id" {
  description = "Matillion agent ID (may be empty until registration)."
  value       = var.agent_id
}

output "client_secret" {
  description = "Matillion Cloud OAuth client secret (sensitive)."
  value       = var.client_secret
  sensitive   = true
}
