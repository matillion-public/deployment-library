
variable "assign_public_ip" {
  description = "Assign public IP - required for image pull if spinning up in a public subnet with no NAT gateway or instance"
  type        = bool
  default     = true
}

variable "name" {
  description = "Name for the ECS Fargate cluster to be created for hosting your agent(s)"
  type        = string
  default     = "data-insights"
}

variable "region" {
  type = string  
}

variable "image_url" {
  description = "The URL of the repository you are pulling the dpc agent image from."
  type        = string
  default     = "public.ecr.aws/matillion/etl-agent:current"
}

variable "account_id" {
  description = "Matillion account ID - This can be acquired from Matillion HUB during the deployment process"
  type        = string
}

variable "agent_id" {
  description = "Matillion Agent ID - This can be acquired from Matillion HUB during the deployment process"
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
  default = ""
}

variable "extension_library_location" {
  description = "Optional: The location for your additional Python libraries."
  type        = string
  default = ""
}

variable "extension_library_protocol" {
  description = "Optional: Used in conjunction with ExtensionLibraryLocation"
  type        = string
  default = ""
}

variable "vpc_id" {
  description = "VPC deployed to by ECS Service"
  type        = string
}

variable "subnet_ids" {
  type = list(string)
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
  description = "Utilize the same ECS cluster while deploying multiple agents"
  type        = list(map(string))
  default     = []
  # Example: [
  # {
  #    agent_name = "",
  #    agent_id = ""
  # } 
  # ]
}

variable "desired_count" {
  type = number
  default = 2
  
}

variable "create_bucket" {
  description = "Used to determine if the referenced bucket should be created, or if should already exist"
  type        = bool
  default     = true
}

variable "agent_task_role_execution_arn" {
  type = string
}

variable "agent_task_role_arn" {
  type = string
}

variable "agent_secret_arn" {
  type = string
  
}

variable "agent_memory" {
  type = number  
}

variable "agent_cpu" {
  type = number  
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