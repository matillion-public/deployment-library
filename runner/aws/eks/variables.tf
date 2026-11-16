resource "random_string" "salt" {
  length  = 8
  numeric = false
  special = false

  lifecycle {
    # Variable validation cannot read is_private_cluster before Terraform 1.9, so the check sits on this resource.
    precondition {
      condition     = var.is_private_cluster || (var.authorized_ip_ranges != null && length(var.authorized_ip_ranges) > 0)
      error_message = "authorized_ip_ranges must be set when is_private_cluster = false. Use [\"<your-office-ip>/32\"], or [\"0.0.0.0/0\"] to allow any address."
    }
  }
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
  default = "10.0.0.0/16"

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
  type        = bool
  default     = true
  description = "When true, the public API server endpoint is disabled and only the private endpoint is available. When false, both are enabled; restrict public access with authorized_ip_ranges."
}

variable "namespace" {
  type        = string
  default     = "matillion"
  description = "Kubernetes namespace the runner is installed into. The IRSA role trusts service accounts in this namespace only."
}

variable "service_account_name" {
  type        = string
  default     = "matillion-runner-sa"
  description = "Runner service account name. Must match serviceAccount.name in the Helm values."
}

variable "script_runner_service_account_name" {
  type        = string
  default     = "matillion-runner-script-runner-sa"
  description = "Script runner service account name. Must match the name the chart renders: scriptRunner.serviceAccount.name, or <fullname>-script-runner-sa when that is empty."
}

variable "authorized_ip_ranges" {
  type        = list(string)
  default     = null
  description = "CIDR blocks allowed to reach the public API endpoint. Required when is_private_cluster = false; use [\"0.0.0.0/0\"] only to allow any address. Optional when is_private_cluster = true; a value set then is still passed to the cluster but applies only while the public endpoint is enabled."
}

variable "authentication_mode" {
  description = "EKS cluster authentication mode: CONFIG_MAP, API_AND_CONFIG_MAP or API. The mode can only be raised on an existing cluster, never lowered."
  type        = string
  default     = "API_AND_CONFIG_MAP"
}

variable "additional_admin_principal_arns" {
  description = "IAM role or user ARNs granted cluster-admin through EKS access entries, in addition to the principal that runs terraform."
  type        = list(string)
  default     = []
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
  description = "Private ECR image URI (arm64) for the SQS->DPC adapter Lambda, in the same region as the function. Lambda will not run an ECR Public image: copy public.ecr.aws/matillion/maia-queue-adapter:<version>-arm64 into your own ECR first (see the maia-queueing-adapter README). Required when enable_sqs_pipeline_trigger = true."
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
