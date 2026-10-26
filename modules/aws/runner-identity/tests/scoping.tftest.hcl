# Run with: terraform test  (from modules/aws/runner-identity)
#
# What a runner's role can and can't reach. Uses a mock provider, so no AWS
# credentials or resources are needed.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
}

variables {
  name                               = "finance"
  oidc_issuer_url                    = "https://oidc.eks.eu-west-1.amazonaws.com/id/ABC123"
  namespace                          = "finance"
  service_account_name               = "finance-sa"
  script_runner_service_account_name = "finance-script-runner-sa"
}

run "role_trusts_only_the_named_service_accounts" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_role.runner.assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.eu-west-1.amazonaws.com/id/ABC123:sub"] == [
      "system:serviceaccount:finance:finance-sa",
      "system:serviceaccount:finance:finance-script-runner-sa",
    ]
    error_message = "The role must trust exactly the named service accounts, in their own namespace."
  }
}

run "no_prefix_grants_no_secret_writes" {
  command = plan

  assert {
    condition     = length(aws_iam_role_policy.secrets_by_prefix) == 0
    error_message = "Without a prefix the runner may only read the secrets listed for it."
  }
}

run "a_prefix_limits_secret_reads_and_writes_to_it" {
  command = plan

  variables {
    secret_name_prefix = "matillion/${var.name}/"
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.secrets_by_prefix[0].policy).Statement[0].Resource == "arn:aws:secretsmanager:*:123456789012:secret:matillion/finance/*"
    error_message = "Reading and writing secrets must be limited to the prefix."
  }

  assert {
    condition     = !contains(jsondecode(aws_iam_role_policy.secrets_by_prefix[0].policy).Statement[0].Action, "secretsmanager:DeleteSecret")
    error_message = "The runner never deletes secrets, so it isn't allowed to."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.secrets_by_prefix[0].policy).Statement[1].Action == ["secretsmanager:ListSecrets"]
    error_message = "Only listing, which returns names, is granted beyond the prefix."
  }
}

run "a_prefix_must_end_in_a_slash" {
  command = plan

  variables {
    secret_name_prefix = "matillion/${substr(var.name, 0, 3)}"
  }

  expect_failures = [var.secret_name_prefix]
}

run "a_prefix_covering_every_runner_is_refused" {
  command = plan

  variables {
    secret_name_prefix = "${split("/", "matillion/x")[0]}/"
  }

  expect_failures = [var.secret_name_prefix]
}
