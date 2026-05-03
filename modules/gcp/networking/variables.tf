variable "name" {
  type = string
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "random_string_salt" {
  type = string
}

variable "enable_cloud_nat" {
  type        = bool
  description = "Enable Cloud NAT for controlled outbound egress with a static IP"
  default     = false
}

variable "tags" {
  type = map(string)
}
