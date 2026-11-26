locals {
  # GCP service account IDs must be 6-30 chars, lowercase letters, numbers, hyphens only
  name_prefix          = substr(lower(replace(var.name, "_", "-")), 0, 16)
  node_sa_account_id   = lookup(var.resource_names, "node_service_account", "${local.name_prefix}-n-${var.random_string_salt}")
  runner_sa_account_id = lookup(var.resource_names, "runner_workload_service_account", "${local.name_prefix}-a-${var.random_string_salt}")
  node_sa_email        = var.existing_node_service_account_email != null ? var.existing_node_service_account_email : google_service_account.gke_node_sa[0].email
  runner_sa_email      = var.existing_runner_workload_service_account_email != null ? var.existing_runner_workload_service_account_email : google_service_account.runner_workload_sa[0].email
  # Project that owns the pre-created runner account, taken from its email.
  runner_sa_project = var.existing_runner_workload_service_account_email != null ? regex("@([a-z][a-z0-9.-]*[a-z0-9])\\.iam\\.gserviceaccount\\.com$", var.existing_runner_workload_service_account_email)[0] : null

  # Fixed to match the Helm chart's default release name, not var.name — see README Workload Identity section.
  k8s_namespace                          = var.k8s_namespace != "" ? var.k8s_namespace : "matillion"
  k8s_service_account_name               = var.k8s_service_account_name != "" ? var.k8s_service_account_name : "matillion-runner-sa"
  script_runner_k8s_service_account_name = var.script_runner_k8s_service_account_name != "" ? var.script_runner_k8s_service_account_name : "matillion-runner-script-runner-sa"
  workload_identity_members = toset([
    "serviceAccount:${var.project_id}.svc.id.goog[${local.k8s_namespace}/${local.k8s_service_account_name}]",
    "serviceAccount:${var.project_id}.svc.id.goog[${local.k8s_namespace}/${local.script_runner_k8s_service_account_name}]",
  ])

  # Flat map of bucket/role pairs for extra GCS bucket permissions
  runner_extra_bucket_roles = {
    for pair in setproduct(var.runner_gcs_buckets, ["roles/storage.legacyBucketReader", "roles/storage.objectViewer"]) :
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
  name     = lookup(var.resource_names, "gke_cluster", join("-", [var.name, "gke-cluster", var.random_string_salt]))
  location = var.region
  project  = var.project_id

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  # The initial pool is deleted straight after creation (remove_default_node_pool), but it is
  # created first, so it must run as the node service account rather than the default compute one.
  node_config {
    service_account = local.node_sa_email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  lifecycle {
    ignore_changes = [node_config]

    precondition {
      condition     = var.grant_node_project_roles || var.existing_node_service_account_email != null
      error_message = "grant_node_project_roles = false requires existing_node_service_account_email. Without it the module creates the node service account and nobody grants it roles/logging.logWriter, roles/monitoring.metricWriter and roles/monitoring.viewer."
    }
  }

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
resource "google_container_node_pool" "runner_nodes" {
  name     = lookup(var.resource_names, "node_pool", join("-", [var.name, "node-pool", var.random_string_salt]))
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

    service_account = local.node_sa_email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = var.labels

    tags = [lookup(var.resource_names, "gke_node_network_tag", join("-", [var.name, "gke-node"]))]

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
  count = var.existing_node_service_account_email == null ? 1 : 0

  account_id   = local.node_sa_account_id
  display_name = "GKE Node Service Account for ${var.name}"
  project      = var.project_id
}

moved {
  from = google_service_account.gke_node_sa
  to   = google_service_account.gke_node_sa[0]
}

resource "google_project_iam_member" "gke_node_log_writer" {
  count = var.grant_node_project_roles ? 1 : 0

  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${local.node_sa_email}"
}

resource "google_project_iam_member" "gke_node_metric_writer" {
  count = var.grant_node_project_roles ? 1 : 0

  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${local.node_sa_email}"
}

resource "google_project_iam_member" "gke_node_monitoring_viewer" {
  count = var.grant_node_project_roles ? 1 : 0

  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${local.node_sa_email}"
}

moved {
  from = google_project_iam_member.gke_node_log_writer
  to   = google_project_iam_member.gke_node_log_writer[0]
}

moved {
  from = google_project_iam_member.gke_node_metric_writer
  to   = google_project_iam_member.gke_node_metric_writer[0]
}

moved {
  from = google_project_iam_member.gke_node_monitoring_viewer
  to   = google_project_iam_member.gke_node_monitoring_viewer[0]
}

# GCP Service Account for Runner Workload Identity
resource "google_service_account" "runner_workload_sa" {
  count = var.existing_runner_workload_service_account_email == null ? 1 : 0

  account_id   = local.runner_sa_account_id
  display_name = "Runner Workload Identity Service Account for ${var.name}"
  project      = var.project_id
}

moved {
  from = google_service_account.runner_workload_sa
  to   = google_service_account.runner_workload_sa[0]
}

# Workload Identity binding: Kubernetes SA -> GCP SA, for the runner account this module creates.
# Covers both the runner SA and the script-runner SA (same GCP identity, different k8s SAs).
# The Kubernetes SAs are created by Helm in the namespace matching var.name.
# depends_on the cluster ensures the Workload Identity pool exists before binding.
resource "google_service_account_iam_binding" "workload_identity_binding" {
  count = var.existing_runner_workload_service_account_email == null ? 1 : 0

  service_account_id = google_service_account.runner_workload_sa[0].name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${local.k8s_namespace}/${local.k8s_service_account_name}]",
    "serviceAccount:${var.project_id}.svc.id.goog[${local.k8s_namespace}/${local.script_runner_k8s_service_account_name}]"
  ]
  depends_on = [google_container_cluster.gke_cluster]
}

moved {
  from = google_service_account_iam_binding.workload_identity_binding
  to   = google_service_account_iam_binding.workload_identity_binding[0]
}

# Workload Identity for a runner account created outside this module. Non-authoritative,
# so members an admin added to roles/iam.workloadIdentityUser on that account are kept.
resource "google_service_account_iam_member" "workload_identity_member" {
  for_each = var.existing_runner_workload_service_account_email != null ? local.workload_identity_members : toset([])

  service_account_id = "projects/${local.runner_sa_project}/serviceAccounts/${var.existing_runner_workload_service_account_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = each.value
  depends_on         = [google_container_cluster.gke_cluster]
}

# GCS Bucket for runner staging storage
resource "google_storage_bucket" "staging" {
  name          = lookup(var.resource_names, "staging_bucket", lower(join("-", [var.name, "staging", var.random_string_salt])))
  location      = var.region
  project       = var.project_id
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = false
  }

  labels = var.labels
}

resource "google_storage_bucket_iam_member" "runner_storage_admin" {
  bucket = google_storage_bucket.staging.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${local.runner_sa_email}"
}

# Secret Manager secret for runner credentials
resource "google_secret_manager_secret" "runner_secret" {
  secret_id = lookup(var.resource_names, "runner_secret", join("-", [var.name, "runner-secret", var.random_string_salt]))
  project   = var.project_id

  replication {
    auto {}
  }

  labels = var.labels
}

resource "google_secret_manager_secret_iam_member" "runner_secret_version_manager" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.runner_secret.secret_id
  role      = "roles/secretmanager.secretVersionManager"
  member    = "serviceAccount:${local.runner_sa_email}"
}

# Custom IAM role granting only the permissions needed to create secrets, populate their first
# version, and set secret-level IAM policies when users define OAuth or Cloud Credentials in the
# Matillion UI. No built-in GCP role grants these without also granting delete/destroy, so a
# custom role is used. The role is not created when existing_runner_secret_creator_role_id
# names one created beforehand.
resource "google_project_iam_custom_role" "runner_secret_creator" {
  count = var.existing_runner_secret_creator_role_id == null ? 1 : 0

  # A role id rejects hyphens. The replace() is only the fallback for a deployment
  # that sets no convention — modules/gcp/naming generates this key in its
  # underscore form, so a convention-supplied name is never rewritten after the
  # uniqueness check has run against it.
  role_id     = lookup(var.resource_names, "runner_secret_creator_role", replace("${local.runner_sa_account_id}_secret_creator", "-", "_"))
  title       = "Runner Secret Creator for ${var.name}"
  description = "Allows the runner SA to create secrets, add their initial version, and set secret-level IAM policies in Secret Manager."
  project     = var.project_id

  permissions = [
    "secretmanager.secrets.create",
    "secretmanager.secrets.setIamPolicy",
    "secretmanager.versions.add",
  ]
}

moved {
  from = google_project_iam_custom_role.runner_secret_creator
  to   = google_project_iam_custom_role.runner_secret_creator[0]
}

resource "google_project_iam_member" "runner_secret_creator" {
  count = var.existing_runner_workload_service_account_email == null ? 1 : 0

  project = var.project_id
  role    = var.existing_runner_secret_creator_role_id != null ? var.existing_runner_secret_creator_role_id : google_project_iam_custom_role.runner_secret_creator[0].name
  member  = "serviceAccount:${local.runner_sa_email}"

  lifecycle {
    precondition {
      condition     = var.existing_runner_secret_creator_role_id == null || startswith(var.existing_runner_secret_creator_role_id, "projects/${var.project_id}/roles/")
      error_message = "existing_runner_secret_creator_role_id must be a custom role in project ${var.project_id}."
    }
  }
}

# Project-wide Secret Manager access — required for the Matillion UI to list and read secrets
resource "google_project_iam_member" "runner_secret_accessor" {
  count = var.existing_runner_workload_service_account_email == null ? 1 : 0

  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${local.runner_sa_email}"
}

# Allows the runner to list/get secret metadata (required for list-secrets in the Matillion UI)
resource "google_project_iam_member" "runner_secret_viewer" {
  count = var.existing_runner_workload_service_account_email == null ? 1 : 0

  project = var.project_id
  role    = "roles/secretmanager.viewer"
  member  = "serviceAccount:${local.runner_sa_email}"
}

# Read access to GCP project metadata (required for the "GCP Project ID" field in the Matillion UI)
resource "google_project_iam_member" "runner_browser" {
  count = var.existing_runner_workload_service_account_email == null ? 1 : 0

  project = var.project_id
  role    = "roles/browser"
  member  = "serviceAccount:${local.runner_sa_email}"
}

moved {
  from = google_project_iam_member.runner_secret_creator
  to   = google_project_iam_member.runner_secret_creator[0]
}

moved {
  from = google_project_iam_member.runner_secret_accessor
  to   = google_project_iam_member.runner_secret_accessor[0]
}

moved {
  from = google_project_iam_member.runner_secret_viewer
  to   = google_project_iam_member.runner_secret_viewer[0]
}

moved {
  from = google_project_iam_member.runner_browser
  to   = google_project_iam_member.runner_browser[0]
}

# Extra GCS bucket read permissions for user-supplied buckets (custom certs, Python libs, external drivers)
resource "google_storage_bucket_iam_member" "runner_extra_bucket_viewer" {
  for_each = local.runner_extra_bucket_roles

  bucket = each.value.bucket
  role   = each.value.role
  member = "serviceAccount:${local.runner_sa_email}"
}

# Additional GCP project (vault) access — each project appears in the Matillion UI's GCP Project ID dropdown
resource "google_project_iam_member" "runner_additional_project_roles" {
  for_each = local.additional_project_roles

  project = each.value.project
  role    = each.value.role
  member  = "serviceAccount:${local.runner_sa_email}"
}
