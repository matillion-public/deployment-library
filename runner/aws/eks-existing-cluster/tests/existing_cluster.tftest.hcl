# Run with: terraform test  (from runner/aws/eks-existing-cluster)
#
# What one runner in a shared cluster can and can't reach. Uses a mock provider, so
# no AWS credentials or resources are needed.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_eks_cluster" {
    defaults = {
      identity = [{ oidc = [{ issuer = "https://oidc.eks.eu-west-1.amazonaws.com/id/ABC123" }] }]
    }
  }
  mock_data "aws_iam_openid_connect_provider" {
    defaults = { url = "oidc.eks.eu-west-1.amazonaws.com/id/ABC123" }
  }
}

variables {
  name         = "finance"
  region       = "eu-west-1"
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
    condition     = output.secret_name_prefix == "matillion/${var.name}/"
    error_message = "Each runner's secrets live under matillion/<name>/."
  }
}

run "script_runner_gets_its_own_role_without_secrets" {
  command = plan

  assert {
    condition     = module.script_runner_identity.secret_name_prefix == ""
    error_message = "The script runner runs people's code, so it must not get the runner's secret access."
  }

  assert {
    condition     = module.script_runner_identity.service_account_name == "finance-script-runner-sa"
    error_message = "The script runner's role must trust only the script runner's service account."
  }
}

run "no_fargate_profile_unless_subnets_are_given" {
  command = plan

  assert {
    condition     = length(aws_eks_fargate_profile.runner) == 0
    error_message = "A cluster with node groups needs no Fargate profile."
  }
}

run "fargate_profile_selects_only_the_runners_namespace" {
  command = plan

  variables {
    fargate_subnet_ids = ["subnet-0abc", "subnet-0def"]
  }

  assert {
    condition     = one(aws_eks_fargate_profile.runner[0].selector).namespace == "finance"
    error_message = "The Fargate profile must select only the runner's namespace."
  }
}

run "rejects_names_iam_or_kubernetes_wont_take" {
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

run "rejects_kubernetes_reserved_namespaces" {
  command = plan

  variables {
    name = "kube-system"
  }

  expect_failures = [var.name]
}

run "rejects_a_name_another_runners_script_runner_uses" {
  command = plan

  variables {
    name = "finance-scripts"
  }

  expect_failures = [var.name]
}
