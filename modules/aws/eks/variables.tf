# modules/aws/eks/variables.tf

variable "name" {
  description = "The name of the EKS cluster"
  type        = string
}

variable "region" {
  description = "The AWS region"
  type        = string
}

variable "subnet_ids" {
  description = "A list of subnet IDs for the EKS cluster control plane"
  type        = list(string)
}

variable "fargate_subnet_ids" {
  description = "A list of private subnet IDs for EKS Fargate profiles"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "A list of security group IDs for the EKS cluster"
  type        = list(string)  
}

variable "endpoint_private_access" {
  description = "Indicates whether or not the API server endpoint is private"
  type        = bool
  
}

variable "endpoint_public_access" {
  description = "Indicates whether or not the API server endpoint is private"
  type        = bool
}

variable "public_access_cidrs" {
  description = "A list of CIDR blocks that are allowed to access the API server endpoint"
  type        = list(string)
}

variable "random_string_salt" {
  description = "A random string to ensure unique resource names"
  type        = string
}

variable "tags" {
  description = "A map of tags to assign to the resources"
  type        = map(string)
}