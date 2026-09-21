###############################################################################
# SQS -> DPC pipeline-execution Lambda adapter ("Option A")
#
# Optional add-on. Consumes messages from an SQS queue and triggers a Maia
# Foundation / DPC pipeline via the DPC pipeline-execution API. The handler is
# distributed as an arm64 container image (see var.image_uri); this module only
# provisions the surrounding AWS resources.
#
# Both the source queue and the project-mapping DynamoDB table can either be
# created by this module or referenced as existing ("bring your own") resources
# via the create_* / existing_* variable pairs. The OAuth secret is always BYO
# (it holds credentials that are provisioned out-of-band).
###############################################################################

variable "name_prefix" {
  description = "Prefix for all resource names created by this module."
  type        = string
  default     = "matillion-maia-sqs-adapter"
}

variable "aws_region" {
  description = "AWS region the adapter runs in."
  type        = string
}

variable "image_uri" {
  description = "Container image URI (arm64) for the SQS->DPC adapter Lambda, e.g. an ECR image reference."
  type        = string
}

# ---------------------------------------------------------------------------
# Source queue: create a new FIFO queue (+DLQ) or use an existing one (BYO).
# ---------------------------------------------------------------------------
variable "create_queue" {
  description = "If true, create the source SQS queue and its dead-letter queue. If false, reference an existing queue via existing_queue_arn/existing_queue_url."
  type        = bool
  default     = true
}

variable "queue_name" {
  description = "Name of the source queue to create (when create_queue = true). A FIFO queue is created, so a '.fifo' suffix is appended if absent."
  type        = string
  default     = "matillion-dpc-requests"
}

variable "existing_queue_arn" {
  description = "ARN of an existing SQS queue to consume from (when create_queue = false)."
  type        = string
  default     = ""
}

variable "existing_queue_url" {
  description = "URL of an existing SQS queue to consume from (when create_queue = false). Only required for operational output; the event source mapping uses the ARN."
  type        = string
  default     = ""
}

variable "fifo_queue" {
  description = "Whether the created source queue is FIFO (matches the reference implementation). Ignored when create_queue = false."
  type        = bool
  default     = true
}

variable "visibility_timeout" {
  description = "Visibility timeout (seconds) for the created source queue."
  type        = number
  default     = 120
}

variable "message_retention_seconds" {
  description = "Message retention (seconds) for the created source queue."
  type        = number
  default     = 345600 # 4 days
}

variable "max_receive_count" {
  description = "Number of receives before a message is moved to the source DLQ (redrive maxReceiveCount)."
  type        = number
  default     = 3
}

# ---------------------------------------------------------------------------
# Project-mapping table: create or BYO.
# ---------------------------------------------------------------------------
variable "create_mapping_table" {
  description = "If true, create the DynamoDB project-mapping table. If false, reference an existing one via existing_mapping_table_name/arn."
  type        = bool
  default     = true
}

variable "mapping_table_name" {
  description = "Name of the project-mapping DynamoDB table to create (when create_mapping_table = true)."
  type        = string
  default     = "matillion-project-mappings"
}

variable "existing_mapping_table_name" {
  description = "Name of an existing project-mapping DynamoDB table (when create_mapping_table = false)."
  type        = string
  default     = ""
}

variable "existing_mapping_table_arn" {
  description = "ARN of an existing project-mapping DynamoDB table (when create_mapping_table = false). The '/index/*' GSI ARN is granted automatically."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# DPC API / OAuth (secret is always BYO).
# ---------------------------------------------------------------------------
variable "secret_name" {
  description = "Name of the pre-existing Secrets Manager secret holding {client_id, client_secret} for DPC OAuth."
  type        = string
}

variable "matillion_api_url" {
  description = "DPC pipeline-execution API base URL."
  type        = string
  default     = "https://eu1.api.matillion.com/dpc/v1"
}

variable "matillion_token_url" {
  description = "DPC OAuth token endpoint."
  type        = string
  default     = "https://id.core.matillion.com/oauth/dpc/token"
}

# ---------------------------------------------------------------------------
# Lambda runtime tuning.
# ---------------------------------------------------------------------------
variable "memory_size" {
  description = "Lambda memory (MB)."
  type        = number
  default     = 512
}

variable "timeout" {
  description = "Lambda timeout (seconds)."
  type        = number
  default     = 60
}

variable "reserved_concurrency" {
  description = "Reserved concurrent executions for the Lambda. -1 leaves it unreserved."
  type        = number
  default     = 20
}

variable "batch_size" {
  description = "SQS event source mapping batch size."
  type        = number
  default     = 10
}

variable "batching_window_seconds" {
  description = "SQS event source mapping maximum batching window (seconds). Ignored when the source queue is FIFO, which Lambda does not allow a batching window on."
  type        = number
  default     = 5
}

variable "log_level" {
  description = "Application log level (MATILLION_LOG_LEVEL)."
  type        = string
  default     = "INFO"
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray active tracing."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention (days) for the Lambda log group."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# Optional observability.
# ---------------------------------------------------------------------------
variable "create_alarms" {
  description = "Create the SNS topic + CloudWatch alarms (DLQ depth, Lambda errors/throttles/duration)."
  type        = bool
  default     = true
}

variable "alarm_dlq_message_threshold" {
  description = "Alarm when the source DLQ has more than this many visible messages."
  type        = number
  default     = 1
}

variable "alarm_lambda_error_threshold" {
  description = "Alarm when Lambda errors exceed this count in the evaluation period."
  type        = number
  default     = 3
}

variable "tags" {
  description = "Additional tags applied to all resources."
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
