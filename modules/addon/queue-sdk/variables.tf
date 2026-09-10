variable "poll_interval_seconds" {
  description = "How often the agent polls the control plane for queued runs via the SDK."
  type        = number
  default     = 10
}

variable "max_concurrent_runs" {
  description = "Maximum concurrent pipeline runs the agent processes."
  type        = number
  default     = 4
}
