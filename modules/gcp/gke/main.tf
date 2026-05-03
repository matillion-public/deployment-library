locals {
  # GCP service account IDs must be 6-30 chars, lowercase letters, numbers, hyphens only
  name_prefix         = substr(lower(replace(var.name, "_", "-")), 0, 16)
  node_sa_account_id  = "${local.name_prefix}-n-${var.random_string_salt}"
  agent_sa_account_id = "${local.name_prefix}-a-${var.random_string_salt}"

  # Workload Identity: fall back to var.name-derived defaults if not explicitly set
  k8s_namespace            = var.k8s_namespace != "" ? var.k8s_namespace : var.name
  k8s_service_account_name = var.k8s_service_account_name != "" ? var.k8s_service_account_name : "${var.name}-sa"

  # Flat map of bucket/role pairs for extra GCS bucket permissions
  agent_extra_bucket_roles = {
    for pair in setproduct(var.agent_gcs_buckets, ["roles/storage.legacyBucketReader", "roles/storage.objectViewer"]) :
    "${pair[0]}/${pair[1]}" => { bucket = pair[0], role = pair[1] }
  }

  # Flat map of project/role pairs for additional GCP project (vault) access
  additional_project_roles = {
    for pair in setproduct(var.additional_gcp_projects, [
      "roles/secretmanager.secretAccessor",
      "roles/secretmanager.viewer",
      "roles/browser"
    ]) :
    "${pair[0]}/${pair[1]}" => { project = pair[0], role = pair[1] }
  }
}

# GKE Cluster
resource "google_container_cluster" "gke_cluster" {
  name     = join("-", [var.name, "gke-cluster", var.random_string_salt])
  location = var.region
  project  = var.project_id

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network_id
  subnetwork = var.subnet_id

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pod_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  dynamic "private_cluster_config" {
    for_each = var.is_private_cluster ? [1] : []
    content {
      enable_private_nodes    = true
      enable_private_endpoint = false
      master_ipv4_cidr_block  = var.master_ipv4_cidr_block
    }
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.authorized_ip_ranges
      content {
        cidr_block = cidr_blocks.value
      }
    }
  }

  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  deletion_protection = false

  resource_labels = var.labels
}

# Separately managed node pool
resource "google_container_node_pool" "agent_nodes" {
  name     = join("-", [var.name, "node-pool", var.random_string_salt])
  location = var.region
  cluster  = google_container_cluster.gke_cluster.name
  project  = var.project_id

  initial_node_count = var.desired_node_count

  autoscaling {
    min_node_count = var.desired_node_count
    max_node_count = var.desired_node_count + 2
  }

  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.node_disk_size
    image_type   = "COS_CONTAINERD"

    # Enable GKE Metadata Server for Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    service_account = google_service_account.gke_node_sa.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = var.labels

    tags = [join("-", [var.name, "gke-node"])]

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# Service Account for GKE nodes
resource "google_service_account" "gke_node_sa" {
  account_id   = local.node_sa_account_id
  display_name = "GKE Node Service Account for ${var.name}"
  project      = var.project_id
}

resource "google_project_iam_member" "gke_node_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

resource "google_project_iam_member" "gke_node_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

resource "google_project_iam_member" "gke_node_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

# GCP Service Account for Agent Workload Identity
resource "google_service_account" "agent_workload_sa" {
  account_id   = local.agent_sa_account_id
  display_name = "Agent Workload Identity Service Account for ${var.name}"
  project      = var.project_id
}

# Workload Identity binding: Kubernetes SA -> GCP SA
# The Kubernetes SA is created by Helm in the namespace matching var.name
# depends_on the cluster ensures the Workload Identity pool exists before binding
resource "google_service_account_iam_binding" "workload_identity_binding" {
  service_account_id = google_service_account.agent_workload_sa.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${local.k8s_namespace}/${local.k8s_service_account_name}]"
  ]
  depends_on = [google_container_cluster.gke_cluster]
}

# GCS Bucket for agent staging storage
resource "google_storage_bucket" "staging" {
  name          = lower(join("-", [var.name, "staging", var.random_string_salt]))
  location      = var.region
  project       = var.project_id
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = false
  }

  labels = var.labels
}

resource "google_storage_bucket_iam_member" "agent_storage_admin" {
  bucket = google_storage_bucket.staging.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.agent_workload_sa.email}"
}

# Secret Manager secret for agent credentials
resource "google_secret_manager_secret" "agent_secret" {
  secret_id = join("-", [var.name, "agent-secret", var.random_string_salt])
  project   = var.project_id

  replication {
    auto {}
  }

  labels = var.labels
}

resource "google_secret_manager_secret_iam_member" "agent_secret_version_manager" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.agent_secret.secret_id
  role      = "roles/secretmanager.secretVersionManager"
  member    = "serviceAccount:${google_service_account.agent_workload_sa.email}"
}

# Custom IAM role granting only the two permissions needed to create secrets and set secret-level
# IAM policies when users define OAuth or Cloud Credentials in the Matillion UI. No built-in GCP
# role grants these without also granting delete/destroy, so a custom role is used.
resource "google_project_iam_custom_role" "agent_secret_creator" {
  role_id     = replace("${local.agent_sa_account_id}_secret_creator", "-", "_")
  title       = "Agent Secret Creator for ${var.name}"
  description = "Allows the agent SA to create secrets and set secret-level IAM policies in Secret Manager."
  project     = var.project_id

  permissions = [
    "secretmanager.secrets.create",
    "secretmanager.secrets.setIamPolicy",
  ]
}

resource "google_project_iam_member" "agent_secret_creator" {
  project = var.project_id
  role    = google_project_iam_custom_role.agent_secret_creator.name
  member  = "serviceAccount:${google_service_account.agent_workload_sa.email}"
}

# Project-wide Secret Manager access — required for the Matillion UI to list and read secrets
resource "google_project_iam_member" "agent_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.agent_workload_sa.email}"
}

# Allows the agent to list/get secret metadata (required for list-secrets in the Matillion UI)
resource "google_project_iam_member" "agent_secret_viewer" {
  project = var.project_id
  role    = "roles/secretmanager.viewer"
  member  = "serviceAccount:${google_service_account.agent_workload_sa.email}"
}

# Read access to GCP project metadata (required for the "GCP Project ID" field in the Matillion UI)
resource "google_project_iam_member" "agent_browser" {
  project = var.project_id
  role    = "roles/browser"
  member  = "serviceAccount:${google_service_account.agent_workload_sa.email}"
}

# Extra GCS bucket read permissions for user-supplied buckets (custom certs, Python libs, external drivers)
resource "google_storage_bucket_iam_member" "agent_extra_bucket_viewer" {
  for_each = local.agent_extra_bucket_roles

  bucket = each.value.bucket
  role   = each.value.role
  member = "serviceAccount:${google_service_account.agent_workload_sa.email}"
}

# Additional GCP project (vault) access — each project appears in the Matillion UI's GCP Project ID dropdown
resource "google_project_iam_member" "agent_additional_project_roles" {
  for_each = local.additional_project_roles

  project = each.value.project
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.agent_workload_sa.email}"
}
