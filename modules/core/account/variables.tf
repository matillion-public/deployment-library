variable "region" {
  description = "Target cloud region for the deployment (e.g. eu-west-1, uksouth, europe-west2)."
  type        = string
}

variable "cloud" {
  description = "Which cloud this deployment targets: aws | azure | gcp. Provider-agnostic — consumed by the compute/auth/networking modules."
  type        = string
  default     = "aws"
  validation {
    condition     = contains(["aws", "azure", "gcp"], var.cloud)
    error_message = "cloud must be one of: aws, azure, gcp."
  }
}

variable "aws_account_id" {
  description = "AWS account ID to deploy into (when cloud = aws). Leave empty to use the provider's default account."
  type        = string
  default     = ""
}

variable "azure_subscription_id" {
  description = "Azure subscription ID to deploy into (when cloud = azure)."
  type        = string
  default     = ""
}

variable "gcp_project_id" {
  description = "GCP project ID to deploy into (when cloud = gcp)."
  type        = string
  default     = ""
}

variable "deployment_name" {
  description = "Short, unique name for this agent deployment. Used to prefix resource names across all composer modules."
  type        = string
  default     = "matillion-agent"
}

variable "tags" {
  description = "Tags/labels applied to all resources created by the composer modules."
  type        = map(string)
  default     = {}
}
