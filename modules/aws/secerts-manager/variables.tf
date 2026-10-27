variable "name" {
  description = "Deployment name. Prefixes the default names of the OAuth credentials and script runner keypair secrets."
  type        = string
  default     = "data-insights"
}

variable "secret_name" {
  description = "Name for the OAuth credentials secret. Defaults to '<name>-oauth-credentials' when empty. The runner receives the secret ARN, so the name can be anything."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to the Secrets Manager secrets"
  type        = map(string)
  default     = {}
}

variable "client_id" {
  description = "The client_id value from the Credentials section of the Matillion runner (Agent) details"
  type        = string
  sensitive   = true
}

variable "client_secret" {
  description = "The client_secret value from the Credentials section of the Matillion runner (Agent) details"
  type        = string
  sensitive   = true
}

variable "enable_keypair_secret" {
  description = "Whether to create a Secrets Manager secret for the script runner SSH keypair."
  type        = bool
  default     = false
}

variable "runner_keypair_secret_name" {
  description = "Name for the Secrets Manager secret holding the script runner SSH authorized_keys. Defaults to '<name>-runner-keypair' when empty."
  type        = string
  default     = ""
}

variable "recovery_window_in_days" {
  description = "Days Secrets Manager keeps a deleted secret before removing it. 0 deletes immediately, so the same name can be reused straight away. The secret values are supplied by Terraform variables and can be recreated."
  type        = number
  default     = 0
}

variable "runner_authorized_keys" {
  description = "SSH public key content to place in the runner's authorized_keys file. Required when enable_keypair_secret is true."
  type        = string
  sensitive   = true
  default     = ""
}
