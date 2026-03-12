resource "random_string" "salt" {
  length  = 6
  numeric = false
  special = false
}

variable "name" {
  type    = string
  default = "matillion-agent"
}

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region for all resources"
}

variable "desired_node_count" {
  type        = number
  description = "Initial number of nodes in the GKE node pool"
  default     = 2
}

variable "machine_type" {
  type        = string
  description = "GCE machine type for GKE nodes"
  default     = "e2-standard-4"
}

variable "node_disk_size" {
  type        = number
  description = "Node boot disk size in GB"
  default     = 100
}

variable "is_private_cluster" {
  type        = bool
  description = "Enable private nodes (nodes have no external IPs). Requires Cloud NAT for egress."
  default     = true
}

variable "master_ipv4_cidr_block" {
  type        = string
  description = "CIDR range reserved for the GKE control-plane internal network (required when is_private_cluster = true)"
  default     = "172.16.0.0/28"
}

variable "authorized_ip_ranges" {
  type        = list(string)
  description = "CIDR blocks authorised to access the GKE API server"
  default     = ["0.0.0.0/0"]
}

variable "enable_cloud_nat" {
  type        = bool
  description = "Enable Cloud NAT so private nodes can reach the internet. Must be true when is_private_cluster = true."
  default     = true
}

variable "labels" {
  type        = map(string)
  description = "Labels applied to all GCP resources"
}
