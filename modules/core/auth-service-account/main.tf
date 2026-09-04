# modules/core/auth-service-account  (GCP)
#
# FOUNDATION resource: the agent service account ("agent_role") =
# google_service_account. core/compute-cloud-run runs the agent as this SA.
# A downloadable key (serviceAccountKey) is created only when explicitly
# requested — Workload Identity is strongly preferred.

locals {
  # SA account IDs must be 6-30 chars, start with a letter, lowercase/digits/hyphens.
  account_id = substr(lower(replace("${var.deployment_name}-agent", "_", "-")), 0, 30)
}

resource "google_service_account" "agent_role" {
  project      = var.project_id
  account_id   = local.account_id
  display_name = "${var.deployment_name} agent service account"
}

resource "google_service_account_key" "agent_role" {
  count              = var.create_service_account_key ? 1 : 0
  service_account_id = google_service_account.agent_role.name
}

# ---------------------------------------------------------------------------
# Least-privilege deploy-time custom role (mirrors the composer contract).
# ---------------------------------------------------------------------------
resource "google_project_iam_custom_role" "deployer" {
  count       = var.create_deployer_role ? 1 : 0
  project     = var.project_id
  role_id     = replace("${var.deployment_name}_auth_service_account_deployer", "-", "_")
  title       = "${var.deployment_name} auth-service-account deployer"
  description = "Least-privilege permissions to provision the core/auth-service-account module."
  permissions = [
    "iam.serviceAccounts.create",
    "iam.serviceAccounts.actAs",
    "secretmanager.versions.access",
  ]
}
