variable "name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "cloudwatch_namespace" {
  description = "CloudWatch namespace for metrics"
  type        = string
  default     = "ECS/AgentSaturation"
}

variable "schedule_expression" {
  description = "EventBridge schedule expression for Lambda execution"
  type        = string
  default     = "rate(1 minute)"
}

variable "log_level" {
  description = "Log level for Lambda function"
  type        = string
  default     = "INFO"
  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR."
  }
}

variable "create_dashboard" {
  description = "Whether to create CloudWatch dashboard"
  type        = bool
  default     = true
}

variable "create_alarms" {
  description = "Whether to create CloudWatch alarms"
  type        = bool
  default     = true
}

variable "high_task_count_threshold" {
  description = "Threshold for high task count alarm"
  type        = number
  default     = 50
}

variable "high_request_count_threshold" {
  description = "Threshold for high request count alarm"
  type        = number
  default     = 20
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarms trigger"
  type        = list(string)
  default     = []
}

variable "agent_service_indicators" {
  description = "Comma-separated list of service name patterns to identify agent services"
  type        = string
  default     = "matillion,agent,dpc"
}

variable "vpc_config" {
  description = "VPC configuration for Lambda function to access ECS tasks"
  type = object({
    vpc_id             = string
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default = null
}

variable "create_vpc_endpoints" {
  description = "Whether to create VPC endpoints for AWS services (recommended for VPC Lambda)"
  type        = bool
  default     = true
}

variable "deployment_mode" {
  description = "Deployment mode: 'public' (Lambda outside VPC, works with public agents), 'private' (Lambda in VPC, works with private agents), 'hybrid' (Lambda outside VPC, tries both public and private IPs)"
  type        = string
  default     = "hybrid"
  validation {
    condition     = contains(["public", "private", "hybrid"], var.deployment_mode)
    error_message = "Deployment mode must be one of: public, private, hybrid."
  }
}

variable "create_internet_access_rules" {
  description = "Whether to create security group rules allowing internet access to agent ports (needed for public agents)"
  type        = bool
  default     = false
}

variable "vpc_endpoint_private_dns_enabled" {
  description = "Enable private DNS for VPC endpoints. Set to false if there are existing VPC endpoints in the VPC."
  type        = bool
  default     = false
}