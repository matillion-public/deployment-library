variable "deployment_name" {
  description = "Deployment name prefix. The agent role is named \"{deployment_name}-agent-role\"."
  type        = string
  default     = "matillion-agent"
}

variable "auth_method" {
  description = "How the agent authenticates to the target account: 'access_key' (agent uses static keys) or 'assume_role' (agent assumes this role, optionally with an external ID)."
  type        = string
  default     = "assume_role"
  validation {
    condition     = contains(["access_key", "assume_role"], var.auth_method)
    error_message = "auth_method must be 'access_key' or 'assume_role'."
  }
}

variable "role_arn" {
  description = "Optional ARN of an external principal permitted to assume the agent role (assume_role auth). Empty means only the ECS tasks service principal may assume it."
  type        = string
  default     = ""
}

variable "external_id" {
  description = "Optional sts:ExternalId required on assume-role (confused-deputy protection). Empty disables the condition."
  type        = string
  default     = ""
}

variable "secret_arns" {
  description = "Secrets Manager secret ARNs the agent role may read at runtime (e.g. the Matillion link client secret). Defaults to the account-scoped Matillion secret path."
  type        = list(string)
  default     = ["*"]
}

variable "create_deployer_policy" {
  description = "Create the least-privilege managed policy describing the permissions a deploying principal needs to provision this module."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to created resources."
  type        = map(string)
  default     = {}
}
