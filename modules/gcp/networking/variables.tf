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

variable "existing_network" {
  type = object({
    network_id                     = string
    subnet_id                      = string
    pod_secondary_range_name       = string
    services_secondary_range_name = string
  })
  description = "Existing VPC network and subnet to use instead of creating new ones. Leave null (default) to create a new VPC and subnet."
  default     = null
}
