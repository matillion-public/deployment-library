variable "name" {
  type        = string
  description = "Name prefix applied to all GCP resources created by this module."
}

variable "project_id" {
  type        = string
  description = "GCP project ID in which all resources are created."
}

variable "region" {
  type        = string
  description = "GCP region for the GKE cluster and associated resources."
}

variable "random_string_salt" {
  type        = string
  description = "Short random suffix appended to resource names to avoid collisions. Pass lower(random_string.salt.result) from the entry-point module."
}

variable "network_id" {
  type        = string
  description = "ID of the VPC network to attach the GKE cluster to."
}

variable "subnet_id" {
  type        = string
  description = "ID of the subnetwork to place GKE nodes in."
}

variable "pod_secondary_range_name" {
  type        = string
  description = "Name of the secondary IP range on the subnet used for GKE pod IPs."
}

variable "services_secondary_range_name" {
  type        = string
  description = "Name of the secondary IP range on the subnet used for GKE service IPs."
}

variable "desired_node_count" {
  type        = number
  description = "Initial and minimum number of nodes in the GKE node pool. Autoscaler allows up to desired_node_count + 2."
  default     = 2
}

variable "machine_type" {
  type        = string
  description = "GCE machine type for GKE node pool."
  default     = "e2-standard-4"
}

variable "node_disk_size" {
  type        = number
  description = "Node boot disk size in GB."
  default     = 100
}

variable "is_private_cluster" {
  type        = bool
  description = "Enable private nodes (nodes have no external IPs). Requires enable_cloud_nat = true for outbound internet access."
  default     = true
}

variable "master_ipv4_cidr_block" {
  type        = string
  description = "CIDR range reserved for the GKE control-plane internal network. Required when is_private_cluster = true. Must be /28 and must not overlap with VPC or pod/service CIDRs."
  default     = "172.16.0.0/28"
}

variable "authorized_ip_ranges" {
  type        = list(string)
  description = "CIDR blocks authorised to access the GKE API server. There is no safe default — set explicitly to your office/VPN CIDRs for private clusters, or [\"0.0.0.0/0\"] only for temporary dev clusters."
}

variable "labels" {
  type        = map(string)
  description = "Labels applied to all GCP resources created by this module."
}

variable "k8s_namespace" {
  type        = string
  description = "Kubernetes namespace the Helm chart is deployed into. Defaults to var.name."
  default     = ""
}

variable "k8s_service_account_name" {
  type        = string
  description = "Kubernetes service account name created by the Helm chart. Defaults to <name>-sa."
  default     = ""
}

variable "agent_gcs_buckets" {
  type        = list(string)
  description = "Extra GCS bucket names to grant the agent read access to (e.g. custom certs, Python libs, external drivers)."
  default     = []
}

variable "additional_gcp_projects" {
  type        = list(string)
  description = "Additional GCP project IDs to grant the agent SA Secret Manager read access to. Each project appears as a separate vault in the Matillion UI alongside the default project."
  default     = []
}
