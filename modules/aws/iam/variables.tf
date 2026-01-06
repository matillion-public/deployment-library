variable "name" {
  description = "Name for the ECS Fargate cluster to be created for hosting your agent(s)"
  type        = string
  default     = "data-insights"
}

variable "agent_secret_arn" {
    type = string
  
}