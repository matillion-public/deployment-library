# Run with: terraform test  (from modules/gcp/runner-identity)
#
# What a runner's service account can and can't reach. Uses a mock provider, so
# no GCP credentials or resources are needed.

mock_provider "google" {
  mock_data "google_project" {
    defaults = { number = "123456789012" }
  }
}

variables {
  name                               = "finance"
  project_id                         = "platform-shared"
  namespace                          = "finance"
  service_account_name               = "finance-sa"
  script_runner_service_account_name = "finance-script-runner-sa"
}

run "binds_only_the_named_service_accounts" {
  command = plan

  assert {
    condition = google_service_account_iam_binding.workload_identity.members == toset([
      "serviceAccount:platform-shared.svc.id.goog[finance/finance-sa]",
      "serviceAccount:platform-shared.svc.id.goog[finance/finance-script-runner-sa]",
    ])
    error_message = "The service account must be bound to exactly the named Kubernetes service accounts, in their own namespace."
  }

  assert {
    condition     = google_service_account.runner.account_id == "finance-runner"
    error_message = "The service account ID is <name>-runner."
  }
}

run "no_prefix_grants_no_secret_writes" {
  command = plan

  assert {
    condition     = length(google_project_iam_member.secrets_by_prefix) == 0 && length(google_project_iam_member.secrets_in_project) == 0
    error_message = "Without a prefix the runner may only read the secrets listed for it."
  }
}

run "a_prefix_limits_secret_reads_and_writes_to_it" {
  command = plan

  variables {
    secret_name_prefix = "matillion_${var.name}_"
  }

  assert {
    condition     = google_project_iam_member.secrets_by_prefix[0].condition[0].expression == "resource.name.startsWith(\"projects/123456789012/secrets/matillion_finance_\")"
    error_message = "Reading and updating secrets must be limited to the prefix, with the project named by number."
  }

  assert {
    condition = toset(google_project_iam_custom_role.secrets_by_prefix[0].permissions) == toset([
      "secretmanager.secrets.get",
      "secretmanager.versions.access",
      "secretmanager.versions.add",
    ])
    error_message = "The conditioned role holds only permissions checked against a secret or version, and never delete or destroy."
  }

  assert {
    condition = toset(google_project_iam_custom_role.secrets_in_project[0].permissions) == toset([
      "resourcemanager.projects.get",
      "secretmanager.secrets.create",
      "secretmanager.secrets.list",
    ])
    error_message = "Only creating and listing, which IAM checks against the project, are granted beyond the prefix."
  }

  assert {
    condition     = length(google_project_iam_member.secrets_in_project[0].condition) == 0
    error_message = "A name condition would never match create or list, which are checked against the project."
  }
}

run "a_prefix_must_end_in_an_underscore" {
  command = plan

  variables {
    secret_name_prefix = "matillion_${substr(var.name, 0, 3)}"
  }

  expect_failures = [var.secret_name_prefix]
}

run "a_one_segment_prefix_is_refused" {
  command = plan

  # "matillion_" would match every runner's secrets.
  variables {
    secret_name_prefix = "matillion_"
  }

  expect_failures = [var.secret_name_prefix]
}

run "a_three_segment_prefix_is_refused" {
  command = plan

  # Everything under "a_b_c_" is also under the two-segment prefix "a_b_", so
  # another runner's prefix would cover it.
  variables {
    secret_name_prefix = "a_b_c_"
  }

  expect_failures = [var.secret_name_prefix]
}

run "a_long_name_keeps_the_truncated_id_it_always_had" {
  command = plan

  # The ID existing deployments already have: "<name>-runner" cut to 30 characters.
  variables {
    name               = "finance-and-accounting-ops"
    secret_name_prefix = "matillion_finance-and-accounting-ops_"
  }

  assert {
    condition     = google_service_account.runner.account_id == "finance-and-accounting-ops-run"
    error_message = "A 26-character name must give the same truncated service account ID as before."
  }

  assert {
    condition = alltrue([
      for id in [
        google_project_iam_custom_role.secrets_by_prefix[0].role_id,
        google_project_iam_custom_role.secrets_in_project[0].role_id,
      ] : can(regex("^[a-zA-Z0-9_.]{3,64}$", id))
    ])
    error_message = "Custom role IDs derived from a truncated service account ID must still be valid role IDs."
  }
}
