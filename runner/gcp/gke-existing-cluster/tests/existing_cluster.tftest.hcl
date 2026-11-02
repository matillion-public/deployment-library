# Run with: terraform test  (from runner/gcp/gke-existing-cluster)
#
# What one runner in a shared cluster can and can't reach. Uses a mock provider, so
# no GCP credentials or resources are needed.

mock_provider "google" {
  mock_data "google_project" {
    defaults = { number = "123456789012" }
  }
  mock_data "google_container_cluster" {
    defaults = {
      name                     = "platform-shared"
      workload_identity_config = [{ workload_pool = "platform-shared.svc.id.goog" }]
    }
  }
}

variables {
  name         = "finance"
  project_id   = "platform-shared"
  location     = "europe-west2"
  cluster_name = "platform-shared"
}

run "names_follow_the_runner" {
  command = plan

  assert {
    condition = (output.namespace == "finance" && output.service_account_name == "finance-sa"
    && output.script_runner_service_account_name == "finance-script-runner-sa")
    error_message = "Each runner's namespace and service accounts are named after it, so runners sharing a cluster never collide."
  }

  assert {
    condition     = output.secret_name_prefix == "matillion_${var.name}_"
    error_message = "Each runner's secrets live under matillion_<name>_."
  }

  assert {
    condition     = module.identity.secret_name_prefix == output.secret_name_prefix
    error_message = "The runner's secret access must be limited to that prefix."
  }
}

run "each_service_account_is_bound_only_to_its_own_kubernetes_service_account" {
  command = plan

  assert {
    condition     = module.identity.workload_identity_members == toset(["serviceAccount:platform-shared.svc.id.goog[finance/finance-sa]"])
    error_message = "The runner's service account must be bound to the runner's Kubernetes service account in its own namespace, and nothing else."
  }

  assert {
    condition     = module.script_runner_identity.workload_identity_members == toset(["serviceAccount:platform-shared.svc.id.goog[finance/finance-script-runner-sa]"])
    error_message = "The script runner's service account must be bound to the script runner's Kubernetes service account in its own namespace, and nothing else."
  }
}

run "script_runner_gets_its_own_service_account_without_secrets" {
  command = plan

  assert {
    condition     = module.script_runner_identity.secret_name_prefix == ""
    error_message = "The script runner runs people's code, so it must not get the runner's secret access."
  }

  assert {
    condition     = length(module.script_runner_identity.scoped_secret_ids) == 0
    error_message = "The script runner must not be granted any secret by ID, or every secret in the project."
  }
}

run "rejects_a_cluster_without_workload_identity" {
  command = plan

  override_data {
    target = data.google_container_cluster.this
    values = { workload_identity_config = [] }
  }

  expect_failures = [data.google_container_cluster.this]
}

run "rejects_names_gcp_or_kubernetes_wont_take" {
  command = plan

  variables {
    name = "Finance_Runner"
  }

  expect_failures = [var.name]
}

run "rejects_a_name_ending_in_a_hyphen" {
  command = plan

  variables {
    name = "finance-"
  }

  expect_failures = [var.name]
}

run "rejects_a_name_too_long_for_a_service_account_id" {
  command = plan

  variables {
    name = "finance-and-accountings"
  }

  expect_failures = [var.name]
}

run "accepts_the_longest_name_that_fits_both_service_account_ids" {
  command = plan

  variables {
    name = "finance-and-accounting"
  }

  # Planning at all means both service accounts' ID checks passed:
  # finance-and-accounting-runner (29) and finance-and-accounting-scripts (30).
  assert {
    condition     = output.namespace == "finance-and-accounting"
    error_message = "A 22-character name must fit both service account IDs within GCP's 30 characters."
  }
}

run "rejects_the_clusters_own_namespaces" {
  command = plan

  variables {
    name = "kube-system"
  }

  expect_failures = [var.name]
}

run "rejects_the_default_namespace" {
  command = plan

  variables {
    name = "default"
  }

  expect_failures = [var.name]
}

run "rejects_a_name_that_is_another_runners_script_runner" {
  command = plan

  # Runner "finance" already has a script runner service account finance-scripts.
  variables {
    name = "finance-scripts"
  }

  expect_failures = [var.name]
}
