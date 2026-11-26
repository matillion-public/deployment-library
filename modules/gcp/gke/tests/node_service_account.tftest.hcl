# Run with: terraform test  (from modules/gcp/gke)
#
# Which service account the cluster's initial node pool and the runner node pool
# run as. Uses a mock provider, so no GCP credentials or resources are needed.

mock_provider "google" {}

override_resource {
  target          = google_service_account.gke_node_sa
  override_during = plan
  values = {
    email = "matillion-runner-n-abcdef@runner-project.iam.gserviceaccount.com"
  }
}

variables {
  name                          = "matillion-runner"
  project_id                    = "runner-project"
  region                        = "europe-west1"
  random_string_salt            = "abcdef"
  network_id                    = "runner-network"
  subnet_id                     = "runner-subnet"
  pod_secondary_range_name      = "pods"
  services_secondary_range_name = "services"
  authorized_ip_ranges          = ["203.0.113.0/24"]
  labels                        = {}
}

run "creates_the_node_service_account_by_default" {
  command = plan

  assert {
    condition     = length(google_service_account.gke_node_sa) == 1
    error_message = "Without an existing node service account the module must create one."
  }

  assert {
    condition     = google_container_cluster.gke_cluster.node_config[0].service_account == "matillion-runner-n-abcdef@runner-project.iam.gserviceaccount.com"
    error_message = "The cluster's initial node pool must run as the created node service account, not the default compute one."
  }

  assert {
    condition     = google_container_node_pool.runner_nodes.node_config[0].service_account == "matillion-runner-n-abcdef@runner-project.iam.gserviceaccount.com"
    error_message = "The runner node pool must run as the created node service account."
  }

  assert {
    condition     = google_project_iam_member.gke_node_log_writer[0].member == "serviceAccount:matillion-runner-n-abcdef@runner-project.iam.gserviceaccount.com"
    error_message = "The created node service account must get the log writer grant."
  }
}

run "uses_a_pre_created_node_service_account" {
  command = plan

  variables {
    existing_node_service_account_email = "runner-nodes@runner-project.iam.gserviceaccount.com"
  }

  assert {
    condition     = length(google_service_account.gke_node_sa) == 0
    error_message = "With an existing node service account the module must not create one."
  }

  assert {
    condition     = google_container_cluster.gke_cluster.node_config[0].service_account == "runner-nodes@runner-project.iam.gserviceaccount.com"
    error_message = "The cluster's initial node pool must run as the pre-created node service account."
  }

  assert {
    condition     = google_container_node_pool.runner_nodes.node_config[0].service_account == "runner-nodes@runner-project.iam.gserviceaccount.com"
    error_message = "The runner node pool must run as the pre-created node service account."
  }

  assert {
    condition = [
      google_project_iam_member.gke_node_log_writer[0].member,
      google_project_iam_member.gke_node_metric_writer[0].member,
      google_project_iam_member.gke_node_monitoring_viewer[0].member,
      ] == [
      "serviceAccount:runner-nodes@runner-project.iam.gserviceaccount.com",
      "serviceAccount:runner-nodes@runner-project.iam.gserviceaccount.com",
      "serviceAccount:runner-nodes@runner-project.iam.gserviceaccount.com",
    ]
    error_message = "The logging and monitoring grants must go to the pre-created node service account."
  }
}

run "rejects_the_default_compute_service_account" {
  command = plan

  variables {
    existing_node_service_account_email = "123456789012-compute@developer.gserviceaccount.com"
  }

  expect_failures = [var.existing_node_service_account_email]
}

run "rejects_a_value_that_is_not_an_email" {
  command = plan

  variables {
    existing_node_service_account_email = "runner-nodes"
  }

  expect_failures = [var.existing_node_service_account_email]
}
