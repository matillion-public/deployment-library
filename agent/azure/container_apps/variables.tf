variable "subscription_id" {
  type        = string
  description = "The subscription ID for the Azure provider"
}

variable "create_key_vault" {
  type        = bool
  default     = true
  description = "Create KeyVault with Template"
}

variable "create_managed_identity" {
  type        = bool
  default     = true
  description = "Create ManagedIdentity with Template"
}

variable "resource_name" {
  type        = string
  description = "The name to use for all resources deployed by this template"
}

variable "location" {
  type        = string
  description = "Specifies the location for all resources."
}

variable "matillion_cloud_region" {
  type        = string
  description = "The Matillion Region of your Agent. Check your Agent details to find the value."
}

variable "subnet_id" {
  type        = string
  description = "The ID of the subnet to deploy the agent into"
}

variable "account_id" {
  type        = string
  description = "Your Account ID. Check your Agent details to find the value."
}

variable "agent_id" {
  type        = string
  description = "The Agent ID of your Agent. Check your Agent details to find the value."
}

variable "client_id" {
  type        = string
  description = "The client_id value from the Credentials section of the Agent details"
}

variable "client_secret" {
  type        = string
  description = "The client_secret value from the Credentials section of the Agent details"
}

variable "container_image_url" {
  type        = string
  default     = "matillion.azurecr.io/cloud-agent:current"
  description = "The agent image URL"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Any tags that you would like to be applied to the created resources"
}

variable "resource_group_name" {
  type        = string
  description = "The name of the resource group where resources will be deployed"
}

variable "key_vault_name" {
  type        = string
  description = "The name of the Key Vault to create or look up"
}

variable "managed_identity_name" {
  type        = string
  description = "The name of the Managed Identity to create or look up"
}

variable "log_analytics_workspace_name" {
  type        = string
  description = "The name of the Log Analytics Workspace"
}
