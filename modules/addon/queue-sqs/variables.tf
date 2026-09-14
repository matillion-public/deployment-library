variable "deployment_name" {
  description = "Deployment name prefix for the queue resources."
  type        = string
  default     = "matillion-agent"
}

variable "agent_service_id" {
  description = "ID of the agent ECS service (from core/compute-ecs). Referenced to establish the trigger_adapter -> agent_service dependency."
  type        = string
}

variable "queue_name" {
  description = "Base name of the trigger queue (\"{deployment_name}-triggers\" when empty)."
  type        = string
  default     = ""
}

variable "visibility_timeout" {
  description = "Visibility timeout (seconds) for the trigger queue."
  type        = number
  default     = 120
}

variable "message_retention_seconds" {
  description = "Message retention (seconds) for the trigger queue."
  type        = number
  default     = 345600
}

variable "max_receive_count" {
  description = "Deliveries before a message is redriven to the DLQ."
  type        = number
  default     = 3
}

variable "adapter_image_uri" {
  description = "ECR image URI for the SQS->DPC trigger adapter Lambda. See README: for production use the richer modules/aws/lambda/sqs-dpc-adapter module (PR #118)."
  type        = string
}

variable "adapter_reserved_concurrency" {
  description = "Reserved concurrent executions for the adapter Lambda."
  type        = number
  default     = 10
}

variable "tags" {
  description = "Tags applied to created resources."
  type        = map(string)
  default     = {}
}

variable "resource_names" {
  description = <<-EOT
    Resource key to explicit name, overriding the generated default. Intended to be
    fed the `names` output of modules/aws/naming, which builds them from a token
    convention. Any key left out keeps its existing generated name, so an empty map
    is exactly today's behaviour.
  EOT
  type        = map(string)
  default     = {}
}
