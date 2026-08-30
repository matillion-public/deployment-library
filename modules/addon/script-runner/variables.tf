variable "cloud" {
  description = "Which cloud the script runner deploys to: aws | azure | gcp. Provisions the provider-native service accordingly."
  type        = string
  validation {
    condition     = contains(["aws", "azure", "gcp"], var.cloud)
    error_message = "cloud must be one of: aws, azure, gcp."
  }
}

variable "deployment_name" {
  description = "Deployment name prefix. The script runner is named \"{deployment_name}-script-runner\"."
  type        = string
  default     = "matillion-agent"
}

variable "agent_service_id" {
  description = "ID of the agent service (from the core/compute-* module). Referenced to establish the script_runner -> agent_service dependency ordering."
  type        = string
}

variable "size" {
  description = "T-shirt size for the script runner."
  type        = string
  default     = "small"
  validation {
    condition     = contains(["small", "medium", "large", "xlarge"], var.size)
    error_message = "size must be one of: small, medium, large, xlarge."
  }
}

variable "image" {
  description = "Script runner container image. Canonical multi-arch image is brbajematillion/maia-script-runner:current."
  type        = string
  default     = "brbajematillion/maia-script-runner:current"
}

variable "ssh_public_key" {
  description = "SSH public key authorised to reach the runner on port 2222. Sensitive; the agent connects to the runner over SSH (no cloud IAM needed)."
  type        = string
  sensitive   = true
}

# --- AWS inputs (cloud = aws) ------------------------------------------------
variable "region" {
  description = "AWS: region."
  type        = string
  default     = ""
}

variable "cluster_arn" {
  description = "AWS: ARN/ID of the ECS cluster to run in (reuses the agent's cluster from core/compute-ecs)."
  type        = string
  default     = ""
}

variable "task_role_arn" {
  description = "AWS: task role ARN for the runner (typically the agent_role)."
  type        = string
  default     = ""
}

variable "execution_role_arn" {
  description = "AWS: ECS task execution role ARN."
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "AWS: subnets the runner service uses."
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "AWS: security groups for the runner tasks (must allow inbound tcp/2222 from the agent)."
  type        = list(string)
  default     = []
}

# --- Azure inputs (cloud = azure) -------------------------------------------
variable "container_app_environment_id" {
  description = "Azure: Container App Environment ID to run the runner in."
  type        = string
  default     = ""
}

variable "resource_group_name" {
  description = "Azure: resource group for the runner container app."
  type        = string
  default     = ""
}

# --- GCP inputs (cloud = gcp) ------------------------------------------------
variable "project_id" {
  description = "GCP: project ID."
  type        = string
  default     = ""
}

variable "gcp_region" {
  description = "GCP: region for the Cloud Run runner."
  type        = string
  default     = ""
}

variable "service_account_email" {
  description = "GCP: service account the runner runs as (typically the agent SA)."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags/labels applied to created resources."
  type        = map(string)
  default     = {}
}
