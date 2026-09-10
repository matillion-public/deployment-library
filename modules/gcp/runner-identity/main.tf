# Per-runner GCP identity: one Google service account per runner deployment,
# bound to that runner's Kubernetes service account through Workload Identity,
# with Secret Manager access granted one secret at a time.
#
# The GCP counterpart of modules/azure/runner-identity. Same reason for
# existing: modules/gcp/gke grants roles/secretmanager.secretAccessor at the
# *project* level, so every runner in the project can read every secret in it.

resource "google_service_account" "runner" {
  account_id   = substr(join("-", [var.name, "runner"]), 0, 30)
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

resource "google_storage_bucket_iam_member" "staging" {
  for_each = toset(var.storage_bucket_names)

  bucket = each.value
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.runner.email}"
}
