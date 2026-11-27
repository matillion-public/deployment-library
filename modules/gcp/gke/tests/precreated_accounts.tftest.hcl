# Run with: terraform test  (from modules/gcp/gke)
#
# A runner service account created outside the module, and turning off the
# node account's project grants. Uses a mock provider, so no GCP credentials or
# resources are needed.

mock_provider "google" {}

override_resource {
  target          = google_service_account.gke_node_sa
  override_during = plan
  values = {
    email = "matillion-runner-n-abcdef@runner-project.iam.gserviceaccount.com"
  }
}

override_resource {
  target          = google_service_account.runner_workload_sa
  override_during = plan
  values = {
    email = "matillion-runner-a-abcdef@runner-project.iam.gserviceaccount.com"
    # The Workload Identity binding validates this as a service account resource name.
    name = "projects/runner-project/serviceAccounts/matillion-runner-a-abcdef@runner-project.iam.gserviceaccount.com"
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

run "creates_the_runner_service_account_by_default" {
  command = plan

  assert {
    condition     = length(google_service_account.runner_workload_sa) == 1
    error_message = "Without an existing runner service account the module must create one."
  }

  assert {
    condition     = length(google_service_account_iam_binding.workload_identity_binding) == 1
    error_message = "The created runner service account must keep its Workload Identity binding."
  }

  assert {
    condition     = length(google_service_account_iam_member.workload_identity_member) == 0
    error_message = "Without an existing runner service account no non-authoritative Workload Identity member is added."
  }

  assert {
    condition     = output.runner_workload_sa_email == "matillion-runner-a-abcdef@runner-project.iam.gserviceaccount.com"
    error_message = "The output must be the created runner service account's email."
  }

  assert {
    condition = [
      length(google_project_iam_member.runner_secret_creator),
      length(google_project_iam_member.runner_secret_accessor),
      length(google_project_iam_member.runner_secret_viewer),
      length(google_project_iam_member.runner_browser),
    ] == [1, 1, 1, 1]
    error_message = "The created runner service account must get the four project grants."
  }

  assert {
    condition = [
      google_project_iam_member.runner_secret_creator[0].member,
      google_project_iam_member.runner_secret_accessor[0].member,
      google_project_iam_member.runner_secret_viewer[0].member,
      google_project_iam_member.runner_browser[0].member,
      ] == [
      "serviceAccount:matillion-runner-a-abcdef@runner-project.iam.gserviceaccount.com",
      "serviceAccount:matillion-runner-a-abcdef@runner-project.iam.gserviceaccount.com",
      "serviceAccount:matillion-runner-a-abcdef@runner-project.iam.gserviceaccount.com",
      "serviceAccount:matillion-runner-a-abcdef@runner-project.iam.gserviceaccount.com",
    ]
    error_message = "The four project grants must go to the created runner service account."
  }

  assert {
    condition = [
      length(google_project_iam_member.gke_node_log_writer),
      length(google_project_iam_member.gke_node_metric_writer),
      length(google_project_iam_member.gke_node_monitoring_viewer),
    ] == [1, 1, 1]
    error_message = "By default the node service account must get its three project grants."
  }
}

run "uses_a_pre_created_runner_service_account" {
  command = plan

  variables {
    existing_runner_workload_service_account_email = "runner-workload@runner-project.iam.gserviceaccount.com"
    runner_gcs_buckets                             = ["certs-bucket"]
    additional_gcp_projects                        = ["vault-project"]
  }

  assert {
    condition     = length(google_service_account.runner_workload_sa) == 0
    error_message = "With an existing runner service account the module must not create one."
  }

  assert {
    condition     = length(google_service_account_iam_binding.workload_identity_binding) == 0
    error_message = "The authoritative Workload Identity binding must not be used on a pre-created runner service account."
  }

  assert {
    condition = toset([for m in google_service_account_iam_member.workload_identity_member : m.member]) == toset([
      "serviceAccount:runner-project.svc.id.goog[matillion/matillion-runner-sa]",
      "serviceAccount:runner-project.svc.id.goog[matillion/matillion-runner-script-runner-sa]",
    ])
    error_message = "Both Kubernetes service accounts must be added as Workload Identity members."
  }

  assert {
    condition = alltrue([
      for m in google_service_account_iam_member.workload_identity_member :
      m.service_account_id == "projects/runner-project/serviceAccounts/runner-workload@runner-project.iam.gserviceaccount.com" && m.role == "roles/iam.workloadIdentityUser"
    ])
    error_message = "The Workload Identity members must be added to the pre-created runner service account with roles/iam.workloadIdentityUser."
  }

  assert {
    condition = [
      length(google_project_iam_member.runner_secret_creator),
      length(google_project_iam_member.runner_secret_accessor),
      length(google_project_iam_member.runner_secret_viewer),
      length(google_project_iam_member.runner_browser),
    ] == [0, 0, 0, 0]
    error_message = "The module must make no project grants to a pre-created runner service account."
  }

  assert {
    condition = alltrue(concat(
      [
        google_storage_bucket_iam_member.runner_storage_admin.member == "serviceAccount:runner-workload@runner-project.iam.gserviceaccount.com",
        google_secret_manager_secret_iam_member.runner_secret_version_manager.member == "serviceAccount:runner-workload@runner-project.iam.gserviceaccount.com",
      ],
      [for m in google_storage_bucket_iam_member.runner_extra_bucket_viewer : m.member == "serviceAccount:runner-workload@runner-project.iam.gserviceaccount.com"],
      [for m in google_project_iam_member.runner_additional_project_roles : m.member == "serviceAccount:runner-workload@runner-project.iam.gserviceaccount.com"],
    ))
    error_message = "The staging bucket, runner secret, extra bucket and additional project grants must go to the pre-created runner service account."
  }

  assert {
    condition     = length(google_project_iam_member.runner_additional_project_roles) == 3
    error_message = "The additional project grants must still be made for a pre-created runner service account."
  }

  assert {
    condition     = output.runner_workload_sa_email == "runner-workload@runner-project.iam.gserviceaccount.com"
    error_message = "The output must be the pre-created runner service account's email."
  }
}

run "takes_the_workload_identity_project_from_the_email" {
  command = plan

  variables {
    existing_runner_workload_service_account_email = "runner-workload@identity-project.iam.gserviceaccount.com"
  }

  assert {
    condition = alltrue([
      for m in google_service_account_iam_member.workload_identity_member :
      m.service_account_id == "projects/identity-project/serviceAccounts/runner-workload@identity-project.iam.gserviceaccount.com"
    ])
    error_message = "The Workload Identity members must be added in the project that owns the runner service account."
  }

  assert {
    condition = toset([for m in google_service_account_iam_member.workload_identity_member : m.member]) == toset([
      "serviceAccount:runner-project.svc.id.goog[matillion/matillion-runner-sa]",
      "serviceAccount:runner-project.svc.id.goog[matillion/matillion-runner-script-runner-sa]",
    ])
    error_message = "The members must use the cluster project's Workload Identity pool."
  }
}

run "rejects_the_default_compute_service_account_as_runner_service_account" {
  command = plan

  variables {
    existing_runner_workload_service_account_email = "123456789012-compute@developer.gserviceaccount.com"
  }

  expect_failures = [var.existing_runner_workload_service_account_email]
}

run "rejects_a_runner_value_that_is_not_an_email" {
  command = plan

  variables {
    existing_runner_workload_service_account_email = "runner-workload"
  }

  expect_failures = [var.existing_runner_workload_service_account_email]
}

run "keeps_node_project_roles_for_a_pre_created_node_account_by_default" {
  command = plan

  variables {
    existing_node_service_account_email = "runner-nodes@runner-project.iam.gserviceaccount.com"
  }

  assert {
    condition = [
      length(google_project_iam_member.gke_node_log_writer),
      length(google_project_iam_member.gke_node_metric_writer),
      length(google_project_iam_member.gke_node_monitoring_viewer),
    ] == [1, 1, 1]
    error_message = "A pre-created node service account must still get the three project grants by default."
  }
}

run "skips_node_project_roles_when_disabled" {
  command = plan

  variables {
    existing_node_service_account_email = "runner-nodes@runner-project.iam.gserviceaccount.com"
    grant_node_project_roles            = false
  }

  assert {
    condition = [
      length(google_project_iam_member.gke_node_log_writer),
      length(google_project_iam_member.gke_node_metric_writer),
      length(google_project_iam_member.gke_node_monitoring_viewer),
    ] == [0, 0, 0]
    error_message = "With grant_node_project_roles = false the module must make no project grants to the node service account."
  }

  assert {
    condition     = google_container_node_pool.runner_nodes.node_config[0].service_account == "runner-nodes@runner-project.iam.gserviceaccount.com"
    error_message = "The runner node pool must run as the pre-created node service account."
  }
}

run "rejects_disabling_node_project_roles_without_a_pre_created_node_account" {
  command = plan

  variables {
    grant_node_project_roles = false
  }

  expect_failures = [google_container_cluster.gke_cluster]
}
