output "poll_interval_seconds" {
  description = "Agent SDK poll interval (seconds)."
  value       = var.poll_interval_seconds
}

output "max_concurrent_runs" {
  description = "Maximum concurrent pipeline runs."
  value       = var.max_concurrent_runs
}
