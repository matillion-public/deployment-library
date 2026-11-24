# Run with: terraform test  (from modules/gcp/gke)
#
# Which custom role the runner service account is granted for creating secrets.
# Uses a mock provider, so no GCP credentials or resources are needed.
#
# Each plan targets the binding (and so the role it reads). The module's
# cluster_ca_certificate output indexes the cluster's master_auth block, which a
# mock provider leaves empty and neither override_resource nor mock_resource can
# fill, so an untargeted plan fails on that output.

mock_provider "google" {}

# Gives the module's own role a known name at plan, so the binding's role can be
# compared with it.
override_resource {
  target          = google_project_iam_custom_role.runner_secret_creator
  override_during = plan
  values = {
    name = "projects/runner-project/roles/matillion_runner_a_abcdef_secret_creator"
  }
}

variables {
  name                          = "matillion-runner"
  project_id                    = "runner-project"
  region                        = "europe-west1"
  random_string_salt            = "abcdef"
  network_id                    = "net"
  subnet_id                     = "subnet"
  pod_secondary_range_name      = "pods"
  services_secondary_range_name = "services"
  authorized_ip_ranges          = ["203.0.113.0/24"]
  labels = {
    environment = "test"
  }
}

run "creates_and_binds_its_own_role_by_default" {
  command = plan

  plan_options {
    target = [google_project_iam_member.runner_secret_creator]
  }

  assert {
    condition     = length(google_project_iam_custom_role.runner_secret_creator) == 1
    error_message = "Without a pre-created role the module creates its own."
  }

  assert {
    condition     = google_project_iam_custom_role.runner_secret_creator[0].role_id == "matillion_runner_a_abcdef_secret_creator"
    error_message = "The role id of the module's own role must not change."
  }

  assert {
    condition     = google_project_iam_member.runner_secret_creator.role == "projects/runner-project/roles/matillion_runner_a_abcdef_secret_creator"
    error_message = "The runner service account is granted the module's own role."
  }

  assert {
    condition = toset(google_project_iam_custom_role.runner_secret_creator[0].permissions) == toset([
      "secretmanager.secrets.create",
      "secretmanager.secrets.setIamPolicy",
      "secretmanager.versions.add",
    ])
    error_message = "The role holds only the permissions to create secrets, add their first version and set their IAM policy."
  }
}

run "binds_a_precreated_role_and_creates_none" {
  command = plan

  plan_options {
    target = [google_project_iam_member.runner_secret_creator]
  }

  variables {
    existing_runner_secret_creator_role_id = "projects/runner-project/roles/matillion_runner_secret_creator"
  }

  assert {
    condition     = length(google_project_iam_custom_role.runner_secret_creator) == 0
    error_message = "With a pre-created role the module creates no custom role."
  }

  assert {
    condition     = google_project_iam_member.runner_secret_creator.role == "projects/runner-project/roles/matillion_runner_secret_creator"
    error_message = "The runner service account is granted the pre-created role."
  }
}

run "rejects_a_bare_role_id" {
  command = plan

  plan_options {
    target = [google_project_iam_member.runner_secret_creator]
  }

  variables {
    existing_runner_secret_creator_role_id = "matillion_runner_secret_creator"
  }

  expect_failures = [var.existing_runner_secret_creator_role_id]
}

run "rejects_a_hyphen_in_the_role_id" {
  command = plan

  plan_options {
    target = [google_project_iam_member.runner_secret_creator]
  }

  variables {
    existing_runner_secret_creator_role_id = "projects/runner-project/roles/matillion-runner-secret-creator"
  }

  expect_failures = [var.existing_runner_secret_creator_role_id]
}

run "rejects_a_role_from_another_project" {
  command = plan

  plan_options {
    target = [google_project_iam_member.runner_secret_creator]
  }

  variables {
    existing_runner_secret_creator_role_id = "projects/other-project/roles/matillion_runner_secret_creator"
  }

  expect_failures = [google_project_iam_member.runner_secret_creator]
}
