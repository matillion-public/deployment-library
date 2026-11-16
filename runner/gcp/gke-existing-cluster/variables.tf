variable "name" {
  type        = string
  description = "The runner's name. It names the runner's namespace, service accounts and secret prefix, so each runner sharing a cluster needs its own. Up to 22 lowercase letters, digits and hyphens, so \"<name>-scripts\" fits a 30-character service account ID; no \"_\", which ends the secret prefix; not \"default\" or \"kube-*\", which are the cluster's namespaces; and not ending in \"-scripts\", which is another runner's script runner service account."

  validation {
    # The script runner's Google service account adds "-scripts", and service
    # account IDs are capped at 30 characters. No "_", because the secret prefix
    # matillion_<name>_ uses it as the delimiter.
    condition     = can(regex("^[a-z]([a-z0-9-]{0,20}[a-z0-9])?$", var.name))
    error_message = "name must start with a lowercase letter, end with a letter or digit, and use only lowercase letters, digits and hyphens, up to 22 characters."
  }

  validation {
    # The name is the runner's namespace. "default" and kube-* belong to the
    # cluster, and a runner there would share them with everything else in it.
    condition     = var.name != "default" && !can(regex("^kube-", var.name))
    error_message = "name is the runner's namespace, so it can't be \"default\" or start with \"kube-\"."
  }

  validation {
    # Runner <x>'s script runner service account is <x>-scripts, so a runner named
    # <x>-scripts would collide with it.
    condition     = !can(regex("-scripts$", var.name))
    error_message = "name can't end in \"-scripts\": runner <x>'s script runner service account is <x>-scripts."
  }
}

variable "project_id" {
  type        = string
  description = "GCP project of the cluster. The runner's service accounts and secrets go in it too, since Workload Identity binds them through the cluster's pool, <project_id>.svc.id.goog."
}

variable "location" {
  type        = string
  description = "Region of a regional cluster, or zone of a zonal one."
}

variable "cluster_name" {
  type        = string
  description = "Name of the existing GKE cluster to deploy the runner into. Workload Identity must already be enabled on it, and on the node pools the runner uses."
}

variable "storage_bucket_names" {
  type        = list(string)
  description = "GCS buckets the runner and script runner may read and write, for staging and loading data. Default none: unlike AWS, the GKE template doesn't grant every bucket either, only the staging bucket it creates and any extra buckets it is given. List the business unit's own buckets, which keeps runners out of each other's data."
  default     = []
}
