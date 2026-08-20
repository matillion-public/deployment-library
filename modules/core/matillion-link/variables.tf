variable "account_id" {
  description = "Matillion account ID (from Matillion Hub during onboarding)."
  type        = string
}

variable "region" {
  description = "Matillion designer/control-plane region (e.g. eu1, us1, ap1)."
  type        = string
  default     = "eu1"
}

variable "client_secret" {
  description = "Matillion Cloud OAuth client secret used to link the agent to the control plane. Sensitive — supply via a secret store / TF_VAR, never commit."
  type        = string
  sensitive   = true
}

variable "agent_id" {
  description = "Optional Matillion agent ID (from Matillion Hub). Empty until the agent is registered."
  type        = string
  default     = ""
}
