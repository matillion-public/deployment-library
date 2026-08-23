variable "name" {
  description = "Name for the ECS Fargate cluster to be created for hosting your runner(s)"
  type        = string
  default     = "data-insights"
}

variable "region" {
  type = string

}

variable "image_url" {
  description = "The URL of the repository you are pulling the dpc-agent image from."
  type        = string
  default     = "public.ecr.aws/matillion/etl-agent:current"
}

variable "account_id" {
  description = "Matillion account ID - This can be acquired from Matillion HUB during the deployment process"
  type        = string
}

variable "agent_id" {
  description = "Matillion runner/agent ID - This can be acquired from Matillion HUB during the deployment process"
  type        = string
}

variable "matillion_region" {
  description = "Matillion designer region"
  type        = string
  default     = "eu1"
}

variable "matillion_environment" {
  description = "Matillion environment - Internal use only"
  type        = string
  default     = ""
}

variable "extension_library_location" {
  description = "Optional: The location for your additional Python libraries."
  type        = string
  default     = ""
}

variable "proxy_http" {
  description = "Optional: HTTP proxy URL for the runner"
  type        = string
  default     = ""
}

variable "proxy_https" {
  description = "Optional: HTTPS proxy URL for the runner"
  type        = string
  default     = ""
}

variable "proxy_excludes" {
  description = "Optional: Comma-separated list of hosts to exclude from proxying"
  type        = string
  default     = ""
}

variable "custom_cert_location" {
  description = "Optional: S3 location of custom certificates"
  type        = string
  default     = ""
}

variable "external_driver_location" {
  description = "Optional: S3 location of external JDBC drivers"
  type        = string
  default     = ""
}

variable "export_logs" {
  description = "Whether to export runner logs (default: true)"
  type        = string
  default     = "true"
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

variable "use_existing_vpc" {
  description = "Whether to use an existing VPC or create a new one"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC deployed to by ECS Service (required if use_existing_vpc is true)"
  type        = string
  default     = null
}

variable "cidr_block" {
  description = "CIDR block for the VPC (required if use_existing_vpc is false)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "use_existing_subnet" {
  description = "Whether to use existing subnets or create new ones"
  type        = bool
  default     = false
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets deployed to by ECS Service (required if use_existing_subnet is true)"
  default     = []
}

variable "use_existing_security_group" {
  description = "Whether to use existing security groups or create a new one"
  type        = bool
  default     = false
}

variable "security_group_ids" {
  description = "A list of the security groups you wish to apply to the tasks in this service (required if use_existing_security_group is true)"
  type        = list(string)
  default     = []
}

variable "create_bucket" {
  description = "Used to determine if the referenced bucket should be created, or if should already exist"
  type        = bool
  default     = true
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "runner_size" {
  description = "T-shirt size for the runner task: small=1vCPU/4GiB, medium=2vCPU/8GiB, large=4vCPU/16GiB, xlarge=8vCPU/32GiB. Each maps to a Fargate-valid cpu/memory pair."
  type        = string
  default     = "small"
  validation {
    condition     = contains(["small", "medium", "large", "xlarge"], var.runner_size)
    error_message = "runner_size must be one of: small, medium, large, xlarge."
  }
}

variable "runner_memory" {
  description = "Override the memory (MiB) derived from runner_size. Leave null to use the size map."
  type        = number
  default     = null
}

variable "runner_cpu" {
  description = "Override the CPU units (1024 = 1 vCPU) derived from runner_size. Leave null to use the size map."
  type        = number
  default     = null
}

variable "ephemeral_storage_size" {
  description = "Optional ephemeral storage size in GiB for the ECS task. If not specified, the default ECS ephemeral storage will be used."
  type        = number
  default     = null
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Any tags that you would like to be applied to the created resources"
}

variable "assign_public_ip" {
  description = "Assign public IP - required for image pull if spinning up in a public subnet with no NAT gateway or instance"
  type        = bool
  default     = true
}

variable "enable_script_runner" {
  description = "Whether to deploy the maia-script-runner service alongside the runner. NOTE: toggling this on an existing deployment modifies the runner ECS service and triggers a rolling task replacement."
  type        = bool
  default     = false
}

variable "script_runner_image_url" {
  description = "Container image for the maia-script-runner."
  type        = string
  default     = "public.ecr.aws/matillion/maia-script-runner:latest"
}

variable "script_runner_size" {
  description = "T-shirt size for the script runner task: small=1vCPU/4GiB, medium=2vCPU/8GiB, large=4vCPU/16GiB, xlarge=8vCPU/32GiB."
  type        = string
  default     = "small"
  validation {
    condition     = contains(["small", "medium", "large", "xlarge"], var.script_runner_size)
    error_message = "script_runner_size must be one of: small, medium, large, xlarge."
  }
}

variable "runner_authorized_keys" {
  description = "SSH public key content for the script runner's authorized_keys. Required when enable_script_runner is true."
  type        = string
  sensitive   = true
  default     = ""
}

variable "runner_keypair_secret_name" {
  description = "Name for the Secrets Manager secret holding the script runner SSH authorized_keys. Defaults to <name>-runner-keypair when not set."
  type        = string
  default     = ""
}

variable "script_runner_extension_library_bucket_arn" {
  description = "Optional: ARN of the S3 bucket used for extension library hydration. Grants narrowly-scoped s3:GetObject and s3:ListBucket to the script runner task role."
  type        = string
  default     = ""
}

variable "script_runner_desired_count" {
  description = "Number of script runner tasks to run."
  type        = number
  default     = 1
}

variable "script_runner_log_retention_days" {
  description = "CloudWatch log retention in days for the script runner task."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# Optional: SQS -> DPC pipeline-execution Lambda adapter ("Option A").
# When enabled, deploys an opt-in Lambda that consumes an SQS queue and triggers
# DPC pipelines. The queue and project-mapping table can be created here or
# referenced as existing (bring-your-own) resources. Disabled by default so
# existing deployments are unaffected.
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
