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
  type = number
  default = 2
}

variable "agent_memory" {
  type = number  
  default = 4096
}

variable "agent_cpu" {
  type = number  
  default = 1024
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