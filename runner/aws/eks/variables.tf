resource "random_string" "salt" {
  length  = 8
  numeric = false
  special = false
}

variable "use_existing_vpc" {
  type    = bool
  default = false
}

variable "existing_vpc_id" {
  type    = string
  default = ""
}

variable "cidr_block" {
  type    = string
  default = "172.5.0.0/16"

}

variable "name" {
  type    = string
  default = "matillion-etl"
}

variable "region" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "use_existing_subnet" {
  type    = bool
  default = false
}

variable "existing_subnet_ids" {
  type    = list(string)
  default = []
}

variable "is_private_cluster" {
  type    = bool
  default = true
}

variable "authorized_ip_ranges" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}
# ---------------------------------------------------------------------------
# Optional: SQS -> DPC pipeline-execution Lambda adapter ("Option A").
# Disabled by default so existing deployments are unaffected.
# ---------------------------------------------------------------------------
variable "enable_sqs_pipeline_trigger" {
  description = "Deploy the optional SQS->DPC pipeline-execution Lambda adapter."
  type        = bool
  default     = false
}

variable "sqs_adapter_image_uri" {
  description = "Container image URI (arm64) for the SQS->DPC adapter Lambda. Required when enable_sqs_pipeline_trigger = true."
  type        = string
  default     = ""
}

variable "sqs_adapter_secret_name" {
  description = "Name of the pre-existing Secrets Manager secret holding {client_id, client_secret} for DPC OAuth."
  type        = string
  default     = "matillion-dpc"
}

variable "sqs_adapter_create_queue" {
  description = "Create the source SQS queue (+DLQ). Set false to consume an existing queue via sqs_adapter_existing_queue_arn."
  type        = bool
  default     = true
}

variable "sqs_adapter_queue_name" {
  description = "Name of the source queue to create (when sqs_adapter_create_queue = true)."
  type        = string
  default     = "matillion-dpc-requests"
}

variable "sqs_adapter_existing_queue_arn" {
  description = "ARN of an existing SQS queue to consume (when sqs_adapter_create_queue = false)."
  type        = string
  default     = ""
}

variable "sqs_adapter_existing_queue_url" {
  description = "URL of an existing SQS queue to consume (when sqs_adapter_create_queue = false)."
  type        = string
  default     = ""
}

variable "sqs_adapter_create_mapping_table" {
  description = "Create the DynamoDB project-mapping table. Set false to use an existing one."
  type        = bool
  default     = true
}

variable "sqs_adapter_mapping_table_name" {
  description = "Name of the project-mapping table to create (when sqs_adapter_create_mapping_table = true)."
  type        = string
  default     = "matillion-project-mappings"
}

variable "sqs_adapter_existing_mapping_table_name" {
  description = "Name of an existing project-mapping table (when sqs_adapter_create_mapping_table = false)."
  type        = string
  default     = ""
}

variable "sqs_adapter_existing_mapping_table_arn" {
  description = "ARN of an existing project-mapping table (when sqs_adapter_create_mapping_table = false)."
  type        = string
  default     = ""
}

variable "sqs_adapter_matillion_api_url" {
  description = "DPC pipeline-execution API base URL."
  type        = string
  default     = "https://eu1.api.matillion.com/dpc/v1"
}

variable "sqs_adapter_matillion_token_url" {
  description = "DPC OAuth token endpoint."
  type        = string
  default     = "https://id.core.matillion.com/oauth/dpc/token"
}
