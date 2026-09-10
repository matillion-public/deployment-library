# modules/core/compute-cloud-run  (GCP)
#
# Declares the agent compute service: agent_service = google_cloud_run_v2_service
# named "{deployment_name}-agent". The service runs as the agent service account
# (agent_role) from core/auth-service-account, making the compute -> auth
# dependency explicit.

locals {
  size_map = {
    small  = { cpu = "1", memory = "2Gi" }
    medium = { cpu = "2", memory = "4Gi" }
    large  = { cpu = "4", memory = "8Gi" }
    xlarge = { cpu = "8", memory = "16Gi" }
  }
  cpu          = local.size_map[var.runner_size].cpu
  memory       = local.size_map[var.runner_size].memory
  service_name = "${var.deployment_name}-agent"
}

resource "google_cloud_run_v2_service" "agent_service" {
  name     = local.service_name
  project  = var.project_id
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  labels   = var.labels

  template {
    service_account = var.agent_service_account_email

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      image = var.image_url
      resources {
        limits = {
          cpu    = local.cpu
          memory = local.memory
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Least-privilege deploy-time custom role (mirrors the composer contract).
# ---------------------------------------------------------------------------
resource "google_project_iam_custom_role" "deployer" {
  count       = var.create_deployer_role ? 1 : 0
  project     = var.project_id
  role_id     = replace("${var.deployment_name}_compute_cloud_run_deployer", "-", "_")
  title       = "${var.deployment_name} compute-cloud-run deployer"
  description = "Least-privilege permissions to provision the core/compute-cloud-run module."
  permissions = [
    "run.services.create",
    "run.services.update",
    "run.services.get",
    "logging.logEntries.create",
  ]
}
