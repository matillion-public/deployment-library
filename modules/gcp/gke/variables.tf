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

variable "network_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "pod_secondary_range_name" {
  type = string
}

variable "services_secondary_range_name" {
  type = string
}

variable "desired_node_count" {
  type    = number
  default = 2
}

variable "machine_type" {
  type        = string
  description = "GCE machine type for GKE node pool"
  default     = "e2-standard-4"
}

variable "node_disk_size" {
  type        = number
  description = "Node disk size in GB"
  default     = 100
}

variable "is_private_cluster" {
  type        = bool
  description = "Enable private nodes (nodes have no external IPs)"
  default     = true
}

variable "master_ipv4_cidr_block" {
  type        = string
  description = "CIDR range for the GKE master network (required when is_private_cluster = true)"
  default     = "172.16.0.0/28"
}

variable "authorized_ip_ranges" {
  type        = list(string)
  description = "CIDR blocks authorised to access the GKE API server"
  default     = ["0.0.0.0/0"]
}

variable "labels" {
  type = map(string)
}
