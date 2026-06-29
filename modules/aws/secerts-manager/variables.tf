variable "name" {
  description = "Name for the ECS Fargate cluster to be created for hosting your runner(s)"
  type        = string
  default     = "data-insights"
}

variable "secret_name" {
  description = "Name for the Secrets Manager secret. The runner expects 'matillion-oauth-credentials' by default."
  type        = string
  default     = "matillion-oauth-credentials"
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
  description = "Name for the Secrets Manager secret holding the script runner SSH authorized_keys."
  type        = string
  default     = "matillion-runner-keypair"
}

variable "runner_authorized_keys" {
  description = "SSH public key content to place in the runner's authorized_keys file. Required when enable_keypair_secret is true."
  type        = string
  sensitive   = true
  default     = ""
}
