variable "deployment_name" {
  description = "Deployment name prefix. The managed identity is named \"{deployment_name}-agent-id\"."
  type        = string
  default     = "matillion-agent"
}

variable "location" {
  description = "Azure region for the managed identity."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to create the managed identity in."
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID."
  type        = string
  default     = ""
}

variable "client_id" {
  description = "Optional application (client) ID associated with the agent identity."
  type        = string
  default     = ""
}

variable "client_secret" {
  description = "Optional application client secret. Sensitive; written to Key Vault when key_vault_id is set. Never commit."
  type        = string
  default     = ""
  sensitive   = true
}

variable "client_secret_expiration_date" {
  description = "RFC3339 expiration date for the Key Vault client secret (rotation deadline). Only used when key_vault_id and client_secret are set."
  type        = string
  default     = "2027-01-01T00:00:00Z"
}

variable "key_vault_id" {
  description = "Optional Key Vault ID. When set, client_secret is stored as a Key Vault secret and the identity is granted Key Vault Secrets User."
  type        = string
  default     = ""
}

variable "role_scope" {
  description = "Scope (subscription or resource-group ID) for the least-privilege deployer role definition."
  type        = string
}

variable "create_deployer_role" {
  description = "Create the least-privilege custom role definition describing the deploy-time permissions this module needs."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to created resources."
  type        = map(string)
  default     = {}
}
