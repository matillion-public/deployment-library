# Run with: terraform test  (from modules/gcp/naming)

variables {
  tokens = {
    bu        = "ng"
    env       = "p"
    env_short = "pd"
    region    = "euw1"
    purpose   = "runner"
    instance  = "01"
  }
}

run "dashed_names_follow_the_convention" {
  command = plan

  assert {
    condition     = output.names["vpc"] == "ng-p-euw1-runner-vpc-01"
    error_message = "vpc was ${output.names["vpc"]}"
  }

  assert {
    condition     = output.names["gke_cluster"] == "ng-p-euw1-runner-gke-01"
    error_message = "gke_cluster was ${output.names["gke_cluster"]}"
  }
}

run "a_custom_role_id_uses_underscores_and_no_hyphens" {
  command = plan

  # google_project_iam_custom_role.role_id rejects hyphens. The module generates
  # the name in the underscore form rather than replacing hyphens afterwards, so
  # the name that is validated is the name that is used.
  assert {
    condition     = output.names["runner_secret_creator_role"] == "ng_p_euw1_runner_secretcreator_01"
    error_message = "runner_secret_creator_role was ${output.names["runner_secret_creator_role"]}"
  }

  assert {
    condition     = length(regexall("-", output.names["runner_secret_creator_role"])) == 0
    error_message = "a hyphen survived into a role id: ${output.names["runner_secret_creator_role"]}"
  }
}

run "a_hyphenated_role_id_fails_the_plan" {
  command = plan

  variables {
    overrides = { runner_secret_creator_role = "ng-p-euw1-runner-secretcreator-01" }
  }

  expect_failures = [output.names]
}

run "a_convention_starting_with_a_digit_fails_the_plan" {
  command = plan

  # RFC1035 requires a leading letter. Azure never needed this check, so it is a
  # genuine addition rather than a copy.
  variables {
    tokens = { bu = "1ng", env = "p", region = "euw1", purpose = "runner", instance = "01" }
  }

  expect_failures = [output.names]
}

run "an_uppercase_token_fails_the_rfc1035_types" {
  command = plan

  variables {
    tokens = { bu = "NG", env = "p", region = "euw1", purpose = "runner", instance = "01" }
  }

  expect_failures = [output.names]
}

run "buckets_are_lowercased_and_keep_their_hyphens" {
  command = plan

  assert {
    condition     = output.names["staging_bucket"] == "ng-p-euw1-staging-gcs-01"
    error_message = "staging_bucket was ${output.names["staging_bucket"]}"
  }
}

run "empty_tokens_do_not_leave_dangling_separators" {
  command = plan

  variables {
    tokens = { bu = "ng", env = "p", region = "euw1" }
  }

  assert {
    condition     = output.names["vpc"] == "ng-p-euw1-vpc"
    error_message = "expected no gap where purpose and instance would be, got ${output.names["vpc"]}"
  }

  # The underscore form collapses to an underscore, not a hyphen — a hyphen would
  # be invalid for the only key that uses this form.
  assert {
    condition     = output.names["runner_secret_creator_role"] == "ng_p_euw1_runner_secretcreator"
    error_message = "runner_secret_creator_role was ${output.names["runner_secret_creator_role"]}"
  }
}

run "service_accounts_fit_inside_thirty_characters" {
  command = plan

  # 30 is the binding constraint on GCP. This convention fits; the README is
  # explicit that a longer one will not, and that overrides are the way out.
  assert {
    condition     = length(output.names["runner_service_account"]) <= 30
    error_message = "runner_service_account is ${length(output.names["runner_service_account"])} characters"
  }

  assert {
    condition     = length(output.names["node_service_account"]) <= 30
    error_message = "node_service_account is ${length(output.names["node_service_account"])} characters"
  }

  assert {
    condition     = output.names["node_service_account"] != output.names["runner_workload_service_account"]
    error_message = "the two GKE service accounts share a name"
  }
}

run "a_convention_too_long_for_a_service_account_fails_the_plan" {
  command = plan

  # The GCP-specific hazard: every service account abbreviates to "sa" and caps at
  # 30 characters. Names are not truncated to fit, precisely because truncating
  # would drop the {type} and {instance} segments and collapse two distinct service
  # accounts onto one identity — so an over-long convention fails here instead.
  variables {
    tokens = {
      bu       = "verylongbusinessunit"
      env      = "production"
      region   = "europewest1"
      purpose  = "runner"
      instance = "01"
    }
  }

  expect_failures = [output.names]
}

run "a_name_below_the_gcp_minimum_fails_the_plan" {
  command = plan

  # GCP enforces minimums as well as maximums: 3 for buckets, 6 for service
  # accounts. Azure has no equivalent, so neither did the module it was copied from.
  variables {
    overrides = { staging_bucket = "ab" }
  }

  expect_failures = [output.names]
}

run "explicit_override_wins" {
  command = plan

  variables {
    overrides = { gke_cluster = "an-existing-cluster" }
  }

  assert {
    condition     = output.names["gke_cluster"] == "an-existing-cluster"
    error_message = "override was not applied, got ${output.names["gke_cluster"]}"
  }

  assert {
    condition     = output.names["node_pool"] == "ng-p-euw1-runner-np-01"
    error_message = "override leaked into other keys"
  }
}

run "custom_format_and_abbreviation" {
  command = plan

  variables {
    formats        = { dashed = "lz{bu}-{env}-{region}-{purpose}-{type}-{instance}" }
    resource_specs = { vpc = { type = "network", max_length = 63, charset = "rfc1035" } }
  }

  assert {
    condition     = output.names["vpc"] == "lzng-p-euw1-runner-network-01"
    error_message = "custom format not applied, got ${output.names["vpc"]}"
  }
}

run "service_accounts_that_share_a_purpose_fail_the_plan" {
  command = plan

  variables {
    resource_specs = {
      node_service_account            = { type = "sa", max_length = 30, charset = "rfc1035", purpose = "shared" }
      runner_workload_service_account = { type = "sa", max_length = 30, charset = "rfc1035", purpose = "shared" }
    }
  }

  expect_failures = [output.names]
}

run "the_default_convention_generates_no_duplicates" {
  command = plan

  assert {
    condition     = length(distinct(values(output.names))) == length(values(output.names))
    error_message = "the default convention generates a duplicate name somewhere"
  }
}

run "a_partial_resource_spec_keeps_the_built_in_attributes" {
  command = plan

  # Changing only the abbreviation must not reset the rest of the spec. A whole-object
  # merge reset max_length to the variable default, so a service account name over
  # GCP's 30-character cap passed the plan and failed at apply.
  variables {
    resource_specs = {
      runner_service_account     = { type = "svcacct" }
      runner_secret_creator_role = { type = "seccreate" }
    }
  }

  assert {
    condition     = output.names["runner_service_account"] == "ng-p-euw1-runner-svcacct-01"
    error_message = "runner_service_account was ${output.names["runner_service_account"]}"
  }

  # form = underscore and charset = role must survive an override mentioning neither.
  assert {
    condition     = output.names["runner_secret_creator_role"] == "ng_p_euw1_runner_seccreate_01"
    error_message = "runner_secret_creator_role lost its underscore form: ${output.names["runner_secret_creator_role"]}"
  }
}

run "a_partial_override_still_respects_the_thirty_character_cap" {
  command = plan

  # Same override, but with a long enough abbreviation to exceed 30. This is the
  # case that silently passed before: max_length reset to 63.
  variables {
    resource_specs = {
      runner_service_account = { type = "averylongserviceaccounttype" }
    }
  }

  expect_failures = [output.names]
}
