# Run with: terraform test  (from runner/gcp/gke)
#
# Inputs for a runner service account created outside this root, and for
# turning off the node account's project grants. Uses a mock google provider,
# so no GCP credentials or resources are needed. The random provider is real,
# so the salt is unknown at plan as on a fresh deployment.

mock_provider "google" {}

# The module's cluster_ca_certificate output indexes the cluster's master_auth
# block, which a mock provider leaves empty and an override can't fill.
override_module {
  target = module.gke
  outputs = {
    cluster_name             = "matillion-runner-gke-cluster-abcdef"
    cluster_endpoint         = "203.0.113.1"
    cluster_ca_certificate   = ""
    runner_workload_sa_email = "runner@runner-project.iam.gserviceaccount.com"
    gcs_bucket_name          = "matillion-runner-staging-abcdef"
    secret_manager_secret_id = "matillion-runner-runner-secret-abcdef"
    auth_config_command      = "gcloud container clusters get-credentials matillion-runner-gke-cluster-abcdef"
  }
}

variables {
  name                 = "matillion-runner"
  project_id           = "runner-project"
  region               = "europe-west1"
  authorized_ip_ranges = ["203.0.113.0/24"]
  labels = {
    environment = "test"
  }
}

run "rejects_disabling_node_project_roles_without_a_pre_created_node_account" {
  command = plan

  variables {
    grant_node_project_roles = false
  }

  expect_failures = [random_string.salt]
}

run "accepts_disabling_node_project_roles_with_a_pre_created_node_account" {
  command = plan

  variables {
    grant_node_project_roles            = false
    existing_node_service_account_email = "runner-nodes@runner-project.iam.gserviceaccount.com"
  }

  assert {
    condition     = var.grant_node_project_roles == false
    error_message = "grant_node_project_roles = false with a pre-created node service account must plan."
  }
}

run "accepts_a_pre_created_runner_service_account_email" {
  command = plan

  variables {
    existing_runner_workload_service_account_email = "runner-workload@runner-project.iam.gserviceaccount.com"
  }

  assert {
    condition     = var.existing_runner_workload_service_account_email == "runner-workload@runner-project.iam.gserviceaccount.com"
    error_message = "A user-managed runner service account email must plan."
  }
}

run "rejects_the_default_compute_service_account_as_runner_service_account" {
  command = plan

  variables {
    existing_runner_workload_service_account_email = "123456789012-compute@developer.gserviceaccount.com"
  }

  expect_failures = [var.existing_runner_workload_service_account_email]
}
