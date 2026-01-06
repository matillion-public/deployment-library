# Variables for Azure State Management Module

variable "account_id" {
  description = "Account identifier for naming resources"
  type        = string
  validation {
    condition     = length(var.account_id) > 0
    error_message = "Account ID must not be empty."
  }
}

variable "resource_group_prefix" {
  description = "Prefix for the resource group name"
  type        = string
  default     = "rg"
}

variable "location" {
  description = "Azure location"
  type        = string
  default     = "East US"
}

variable "principal_ids" {
  description = "List of principal IDs (service principals, users, managed identities) allowed to access the state storage"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}