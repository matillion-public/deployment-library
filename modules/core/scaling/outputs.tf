output "min_agents" {
  description = "Minimum agent replica count."
  value       = var.min_agents
}

output "max_agents" {
  description = "Maximum agent replica count."
  value       = var.max_agents
}

output "autoscale" {
  description = "Whether autoscaling is enabled."
  value       = var.autoscale
}

output "desired_agents" {
  description = "Effective desired replica count (equals min_agents; the autoscaler manages the range when autoscale = true)."
  value       = local.desired_agents
}
