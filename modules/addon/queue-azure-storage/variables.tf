variable "deployment_name" {
  description = "Deployment name prefix. Used to derive the storage account name (3-24 lowercase alphanumerics)."
  type        = string
  default     = "matillion-agent"
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to create the storage account + queue in."
  type        = string
}

variable "agent_principal_id" {
  description = "Principal (object) ID of the agent managed identity from core/auth-msi (agent_role). The trigger_role_assignment grants it queue-message access."
  type        = string
}

variable "queue_name" {
  description = "Name of the trigger storage queue (\"{deployment_name}-triggers\" when empty)."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to created resources."
  type        = map(string)
  default     = {}
}

variable "resource_names" {
  description = <<-EOT
    Resource key to explicit name, overriding the generated default. Intended to be
    fed the `names` output of modules/azure/naming, which builds them from a token
    convention. Any key left out keeps its existing generated name, so an empty map
    is exactly today's behaviour.
  EOT
  type        = map(string)
  default     = {}
}
