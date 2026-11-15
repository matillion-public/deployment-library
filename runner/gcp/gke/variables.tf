variable "name" {
  type    = string
  default = "matillion-runner"

  validation {
    # The cluster is named <name>-gke-cluster-<6-character salt>, and GKE cluster
    # names are capped at 40 characters: 40 - 13 - 6 = 21.
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.name)) && length(var.name) <= 21
    error_message = "name must start with a lowercase letter, end with a lowercase letter or digit, use only lowercase letters, digits and hyphens, and be at most 21 characters."
  }
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
  description = "Initial and minimum number of nodes per zone in the GKE node pool. The cluster is regional, so the pool runs in every zone of the region and the total is this value times the number of zones. The autoscaler allows up to desired_node_count + 2 per zone."
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
  description = "CIDR blocks authorised to access the GKE API server. There is no safe default — set this explicitly to your office/VPN CIDRs for private clusters, or to [\"0.0.0.0/0\"] only for temporary dev clusters."

  validation {
    condition     = alltrue([for range in var.authorized_ip_ranges : can(cidrhost(range, 0))])
    error_message = "Each authorized_ip_ranges entry must be a CIDR block with a prefix length, e.g. 203.0.113.0/24."
  }
}

variable "enable_cloud_nat" {
  type        = bool
  description = "Enable Cloud NAT so private nodes can reach the internet. Must be true when is_private_cluster = true."
  default     = true
}

variable "existing_network" {
  type = object({
    network_id                    = string
    subnet_id                     = string
    pod_secondary_range_name      = string
    services_secondary_range_name = string
  })
  description = "Existing VPC network and subnet to deploy into instead of creating new ones. Leave null (default) to create a new VPC and subnet."
  default     = null
}

variable "labels" {
  type        = map(string)
  description = "Labels applied to all GCP resources"

  validation {
    condition = alltrue([
      for key, value in var.labels :
      can(regex("^[a-z][a-z0-9_-]{0,62}$", key)) && can(regex("^[a-z0-9_-]{0,63}$", value))
    ])
    error_message = "Label keys must start with a lowercase letter and use only lowercase letters, digits, \"_\" and \"-\", up to 63 characters. Label values must use only lowercase letters, digits, \"_\" and \"-\", up to 63 characters."
  }
}

variable "k8s_namespace" {
  type        = string
  description = "Kubernetes namespace the Helm chart is deployed into. Defaults to \"matillion\". Not tied to var.name."
  default     = ""
}

variable "k8s_service_account_name" {
  type        = string
  description = "Kubernetes service account name created by the Helm chart. Defaults to \"matillion-runner-sa\". Not tied to var.name."
  default     = ""
}

variable "script_runner_k8s_service_account_name" {
  type        = string
  description = "Kubernetes service account name for the script-runner pod. Defaults to \"matillion-runner-script-runner-sa\". Not tied to var.name."
  default     = ""
}

variable "runner_gcs_buckets" {
  type        = list(string)
  description = "Extra GCS bucket names to grant the runner read access to (e.g. custom certs, Python libs, external drivers)."
  default     = []
}

variable "additional_gcp_projects" {
  type        = list(string)
  description = "Additional GCP project IDs to grant the runner SA Secret Manager read access to. Each project appears as a separate vault in the Matillion UI alongside the default project."
  default     = []
}
