
variable "assign_public_ip" {
  description = "Assign public IP - required for image pull if spinning up in a public subnet with no NAT gateway or instance"
  type        = bool
  default     = true
}

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
  description = "Matillion Agent ID (API contract field name) - This can be acquired from Matillion HUB during the deployment process"
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

variable "vpc_id" {
  description = "VPC deployed to by ECS Service"
  type        = string
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets deployed to by ECS Service"

}

variable "secret_arns" {
  description = "A list of secret ARNs the task role needs access to - specifically the Private Key and DB Password secrets"
  type        = list(string)
  default     = ["*"]
}

variable "security_group_ids" {
  description = "A list of the security groups you wish to apply to the tasks in this service"
  type        = list(string)
}


variable "task_and_service_definitions" {
  description = "Utilize the same ECS cluster while deploying multiple runners"
  type        = list(map(string))
  default     = []
  # Example: [
  # {
  #    runner_name = "",
  #    agent_id = ""
  # }
  # ]
}

variable "desired_count" {
  type    = number
  default = 2

}

variable "create_bucket" {
  description = "Used to determine if the referenced bucket should be created, or if should already exist"
  type        = bool
  default     = true
}

variable "runner_task_role_execution_arn" {
  type = string
}

variable "runner_task_role_arn" {
  type = string
}

variable "runner_secret_arn" {
  type = string
}

variable "runner_size" {
  description = "T-shirt size for the runner task. Maps to a Fargate-valid cpu/memory pair: small=1vCPU/4GiB, medium=2vCPU/8GiB, large=4vCPU/16GiB, xlarge=8vCPU/32GiB."
  type        = string
  default     = "small"
  validation {
    condition     = contains(["small", "medium", "large", "xlarge"], var.runner_size)
    error_message = "runner_size must be one of: small, medium, large, xlarge."
  }
}

variable "runner_memory" {
  description = "Override the memory (MiB) derived from runner_size. Leave null to use the size map. Must be a Fargate-valid combination with runner_cpu."
  type        = number
  default     = null
}

variable "runner_cpu" {
  description = "Override the CPU units (1024 = 1 vCPU) derived from runner_size. Leave null to use the size map. Must be a Fargate-valid combination with runner_memory."
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

variable "enable_script_runner" {
  description = "Whether to deploy the maia-script-runner service alongside the agent. Enables Service Connect on both services. NOTE: toggling this on an existing deployment modifies the agent ECS service and triggers a rolling task replacement. IMPORTANT: ECS Service Connect proxy sidecars snapshot the namespace at task launch — if the script-runner alias/port/topology ever changes after the agent tasks are running, the agent tasks must be redeployed to pick up the new alias. This is inherent to Service Connect and cannot be worked around in Terraform."
  type        = bool
  default     = false
}

variable "script_runner_image_url" {
  description = "Container image for the maia-script-runner. Only used when enable_script_runner is true."
  type        = string
  default     = "public.ecr.aws/matillion/maia-script-runner:current"
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

variable "runner_keypair_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the runner SSH authorized_keys. Required when enable_script_runner is true."
  type        = string
  default     = ""
}

variable "script_runner_task_role_arn" {
  description = "ARN of the narrow IAM task role for the script runner. Required when enable_script_runner is true."
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
