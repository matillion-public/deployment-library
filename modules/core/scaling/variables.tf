variable "min_agents" {
  description = "Minimum number of agent replicas."
  type        = number
  default     = 1
  validation {
    condition     = var.min_agents >= 0
    error_message = "min_agents must be >= 0."
  }
}

variable "max_agents" {
  description = "Maximum number of agent replicas."
  type        = number
  default     = 5
  validation {
    condition     = var.max_agents >= 1
    error_message = "max_agents must be >= 1."
  }
}

variable "autoscale" {
  description = "Whether the platform should autoscale agent replicas between min_agents and max_agents. When false, min_agents is used as a fixed replica count."
  type        = bool
  default     = false
}
