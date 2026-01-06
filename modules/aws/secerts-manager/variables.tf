variable "name" {
  description = "Name for the ECS Fargate cluster to be created for hosting your agent(s)"
  type        = string
  default     = "data-insights"
}

variable "client_id" {
  description = "The client_id value from the Credentials section of the Agent details"
  type        = string
  sensitive = true
}

variable "client_secret" {
  description = "The client_secret value from the Credentials section of the Agent details"
  type        = string
  sensitive = true
}