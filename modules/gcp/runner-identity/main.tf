# Per-runner GCP identity: one Google service account per runner deployment,
# bound to that runner's Kubernetes service account through Workload Identity.
# Secret Manager access is either read only, one secret at a time, or read and
# write under one secret name prefix.
#
# The GCP counterpart of modules/azure/runner-identity. Same reason for
# existing: modules/gcp/gke grants roles/secretmanager.secretAccessor at the
# *project* level, so every runner in the project can read every secret in it.

locals {
  # Truncated to the 30-character service account ID limit, as it always has been,
  # so existing accounts keep their IDs. Two long names that share their first 23
  # characters truncate to the same ID; runner/gcp/gke-existing-cluster limits
  # name so it never truncates.
  account_id = lookup(var.resource_names, "runner_service_account", substr(join("-", [var.name, "runner"]), 0, 30))
}

resource "google_service_account" "runner" {
  account_id   = local.account_id
  display_name = "Matillion runner (${var.name})"
  project      = var.project_id
}

# Binds the Google service account to exactly the Kubernetes service accounts
# named here. A runner deployed under a different serviceAccount.name gets no
# credentials rather than falling back to another tenant's identity.
resource "google_service_account_iam_binding" "workload_identity" {
  service_account_id = google_service_account.runner.name
  role               = "roles/iam.workloadIdentityUser"

  members = compact([
    "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${var.service_account_name}]",
    var.script_runner_service_account_name != "" ? "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${var.script_runner_service_account_name}]" : "",
  ])
}

# One IAM member per secret, bound to the individual secret rather than the
# project. This is the whole point of the module.
resource "google_secret_manager_secret_iam_member" "secret_accessor" {
  for_each = toset(var.secret_ids)

  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runner.email}"
}

# Escape hatch for deployments that create secrets at runtime and so cannot
# enumerate them at plan time. Grants access to every secret in the project and
# therefore gives up the isolation this module exists to provide — off by
# default.
resource "google_project_iam_member" "project_wide_secret_accessor" {
  count = var.grant_project_wide_secret_access ? 1 : 0

  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.runner.email}"
}

data "google_project" "this" {
  count = var.secret_name_prefix != "" ? 1 : 0

  project_id = var.project_id
}

# Read and update for every secret under the runner's prefix: reading a secret's
# metadata, reading its value, and adding a version, which is how the runner saves
# a new value. The condition is the only thing scoping the grant, so the role
# holds nothing that is checked against anything but a secret or a version.
# IAM names secrets by project number, not ID, in resource.name.
resource "google_project_iam_custom_role" "secrets_by_prefix" {
  count = var.secret_name_prefix != "" ? 1 : 0

  role_id     = lookup(var.resource_names, "runner_secret_prefix_role", "${replace(local.account_id, "-", "_")}_secret_prefix")
  title       = "Matillion runner secrets under ${var.secret_name_prefix}"
  description = "Read secrets and add versions. Granted with a condition limiting it to one runner's secret name prefix."
  project     = var.project_id
  permissions = [
    "secretmanager.secrets.get",
    "secretmanager.versions.access",
    "secretmanager.versions.add",
  ]
}

resource "google_project_iam_member" "secrets_by_prefix" {
  count = var.secret_name_prefix != "" ? 1 : 0

  project = var.project_id
  role    = google_project_iam_custom_role.secrets_by_prefix[0].name
  member  = "serviceAccount:${google_service_account.runner.email}"

  condition {
    title       = "Secrets under ${var.secret_name_prefix}"
    description = "Secrets and secret versions whose IDs start with ${var.secret_name_prefix}"
    expression  = "resource.name.startsWith(\"projects/${data.google_project.this[0].number}/secrets/${var.secret_name_prefix}\")"
  }
}

# Creating and listing secrets are checked against the project, not the secret,
# so a condition on the secret's name can never match them: they are granted on
# the whole project instead. Creating a secret gives the runner no access to it
# unless its name is under the prefix. Listing returns every secret's metadata in
# the project, never a value. resourcemanager.projects.get lets the runner find
# its own project, which Matillion offers as the place to keep secrets.
resource "google_project_iam_custom_role" "secrets_in_project" {
  count = var.secret_name_prefix != "" ? 1 : 0

  role_id     = lookup(var.resource_names, "runner_secret_project_role", "${replace(local.account_id, "-", "_")}_secret_project")
  title       = "Matillion runner secret creation (${var.name})"
  description = "Create and list secrets in the project. IAM checks both against the project, so neither can be limited to a name prefix."
  project     = var.project_id
  permissions = [
    "resourcemanager.projects.get",
    "secretmanager.secrets.create",
    "secretmanager.secrets.list",
  ]
}

resource "google_project_iam_member" "secrets_in_project" {
  count = var.secret_name_prefix != "" ? 1 : 0

  project = var.project_id
  role    = google_project_iam_custom_role.secrets_in_project[0].name
  member  = "serviceAccount:${google_service_account.runner.email}"
}

resource "google_storage_bucket_iam_member" "staging" {
  for_each = toset(var.storage_bucket_names)

  bucket = each.value
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.runner.email}"
}
