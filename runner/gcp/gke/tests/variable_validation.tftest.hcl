# Run with: terraform test  (from runner/gcp/gke)
#
# Inputs GCP would reject at apply, after other resources exist, must fail at plan.
# Uses a mock provider, so no GCP credentials or resources are needed.

mock_provider "google" {}

mock_provider "random" {}

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

run "accepts_lowercase_name_labels_and_a_cidr_range" {
  command = plan

  assert {
    condition     = var.name == "matillion-runner"
    error_message = "A lowercase name, lowercase labels and a CIDR range with a prefix length must plan."
  }
}

run "accepts_the_longest_name_that_fits_the_cluster_name" {
  command = plan

  variables {
    name = "matillion-runner-0123"
  }

  # matillion-runner-0123-gke-cluster-<salt> is 40 characters, GKE's limit.
  assert {
    condition     = length(var.name) == 21
    error_message = "A 21-character name must fit GKE's 40-character cluster name."
  }
}

run "rejects_an_uppercase_name" {
  command = plan

  variables {
    name = "Matillion-Runner"
  }

  expect_failures = [var.name]
}

run "rejects_a_name_too_long_for_the_cluster_name" {
  command = plan

  variables {
    name = "matillion-runner-01234"
  }

  expect_failures = [var.name]
}

run "rejects_an_uppercase_label_value" {
  command = plan

  variables {
    labels = {
      environment = "Test"
    }
  }

  expect_failures = [var.labels]
}

run "rejects_an_authorized_ip_range_without_a_prefix_length" {
  command = plan

  variables {
    authorized_ip_ranges = ["10.0.0.1"]
  }

  expect_failures = [var.authorized_ip_ranges]
}
