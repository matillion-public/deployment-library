# Run with: terraform test  (from modules/aws/naming)

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
    condition     = output.names["ecs_cluster"] == "ng-p-euw1-runner-ecs-01"
    error_message = "ecs_cluster was ${output.names["ecs_cluster"]}"
  }

  assert {
    condition     = output.names["nat_gateway"] == "ng-p-euw1-runner-natgw-01"
    error_message = "nat_gateway was ${output.names["nat_gateway"]}"
  }
}

run "log_groups_keep_their_mandated_path_prefix" {
  command = plan

  # The /ecs/ segment is a convention choice, so it lives on the spec as a prefix
  # rather than in the format. There is deliberately no key for the Lambda log
  # groups: AWS fixes those at /aws/lambda/<function-name>.
  assert {
    condition     = output.names["ecs_task_log_group"] == "/ecs/ng-p-euw1-runner-log-01"
    error_message = "ecs_task_log_group was ${output.names["ecs_task_log_group"]}"
  }

  assert {
    condition     = output.names["script_runner_log_group"] == "/ecs/ng-p-euw1-scriptrunner-log-01"
    error_message = "script_runner_log_group was ${output.names["script_runner_log_group"]}"
  }

  assert {
    condition     = !contains(keys(output.names), "saturation_log_group")
    error_message = "Lambda log groups must not be independently nameable"
  }
}

run "a_log_group_without_its_leading_slash_fails_the_plan" {
  command = plan

  variables {
    overrides = { ecs_task_log_group = "ecs/no-leading-slash" }
  }

  expect_failures = [output.names]
}

run "s3_buckets_are_lowercased" {
  command = plan

  variables {
    tokens = {
      bu       = "NG"
      env      = "P"
      region   = "EUW1"
      purpose  = "Staging"
      instance = "01"
    }
  }

  assert {
    condition     = output.names["staging_bucket"] == "ng-p-euw1-staging-s3-01"
    error_message = "staging_bucket was ${output.names["staging_bucket"]}"
  }

  # Unlike Azure storage accounts, S3 keeps its hyphens — lowercase and
  # separator-free are separate constraints.
  assert {
    condition     = length(regexall("-", output.names["state_bucket"])) > 0
    error_message = "state_bucket lost its hyphens: ${output.names["state_bucket"]}"
  }
}

run "empty_tokens_do_not_leave_dangling_separators" {
  command = plan

  variables {
    tokens = { bu = "ng", env = "p", region = "euw1" }
  }

  assert {
    condition     = output.names["ecs_cluster"] == "ng-p-euw1-ecs"
    error_message = "expected no gap where purpose and instance would be, got ${output.names["ecs_cluster"]}"
  }

  # The prefix must survive the tidy that strips leading separators.
  assert {
    condition     = output.names["ecs_task_log_group"] == "/ecs/ng-p-euw1-log"
    error_message = "ecs_task_log_group was ${output.names["ecs_task_log_group"]}"
  }
}

run "explicit_override_wins" {
  command = plan

  variables {
    overrides = { ecs_cluster = "legacy-cluster-name" }
  }

  assert {
    condition     = output.names["ecs_cluster"] == "legacy-cluster-name"
    error_message = "override was not applied, got ${output.names["ecs_cluster"]}"
  }

  assert {
    condition     = output.names["eks_cluster"] == "ng-p-euw1-runner-eks-01"
    error_message = "override leaked into other keys"
  }
}

run "custom_format_and_abbreviation" {
  command = plan

  variables {
    formats        = { dashed = "lz{bu}-{env}-{region}-{purpose}-{type}-{instance}" }
    resource_specs = { ecs_cluster = { type = "cluster", form = "dashed", max_length = 255 } }
  }

  assert {
    condition     = output.names["ecs_cluster"] == "lzng-p-euw1-runner-cluster-01"
    error_message = "custom format not applied, got ${output.names["ecs_cluster"]}"
  }
}

run "an_iam_role_over_64_characters_fails_the_plan" {
  command = plan

  # 64 is the binding constraint across the IAM-heavy modules, so this is the
  # limit a real convention is most likely to break.
  variables {
    overrides = { eks_role = "an-extremely-long-business-unit-name-that-will-not-fit-inside-the-iam-role-limit" }
  }

  expect_failures = [output.names]
}

run "roles_that_share_an_abbreviation_get_distinct_names" {
  command = plan

  # Every IAM role abbreviates to "role", so the per-key purpose is what keeps
  # them apart. A collision would surface as a duplicate resource name on apply.
  assert {
    condition     = output.names["eks_role"] != output.names["runner_role"]
    error_message = "eks_role and runner_role both resolved to ${output.names["eks_role"]}"
  }

  assert {
    condition     = output.names["eks_role"] == "ng-p-euw1-eks-role-01"
    error_message = "eks_role was ${output.names["eks_role"]}"
  }

  assert {
    condition     = length(distinct(values(output.names))) == length(values(output.names))
    error_message = "the default convention generates a duplicate name somewhere"
  }
}

run "a_convention_that_collides_fails_the_plan" {
  command = plan

  variables {
    resource_specs = {
      eks_role    = { type = "role", max_length = 64, charset = "iam", purpose = "shared" }
      runner_role = { type = "role", max_length = 64, charset = "iam", purpose = "shared" }
    }
  }

  expect_failures = [output.names]
}

run "a_fifo_suffix_is_applied_and_counted_against_the_limit" {
  command = plan

  # A FIFO queue's name must end ".fifo". Naming only the suffix also exercises the
  # per-attribute merge: type, charset, purpose and max_length come from the
  # built-in spec.
  variables {
    resource_specs = {
      adapter_source_queue = { suffix = ".fifo" }
    }
  }

  assert {
    condition     = output.names["adapter_source_queue"] == "ng-p-euw1-sqssource-sqs-01.fifo"
    error_message = "adapter_source_queue was ${output.names["adapter_source_queue"]}"
  }
}

run "a_suffix_that_pushes_a_name_over_the_limit_fails_the_plan" {
  command = plan

  # The suffix counts against max_length. The name is not truncated to make room —
  # that would drop the {instance} discriminator.
  variables {
    resource_specs = {
      adapter_source_queue = { max_length = 28, suffix = ".fifo" }
    }
  }

  expect_failures = [output.names]
}

run "a_security_group_name_starting_with_sg_fails_the_plan" {
  command = plan

  # AWS reserves the "sg-" prefix for the generated group id. Reachable for real:
  # a business unit abbreviated "sg" produces exactly this.
  variables {
    tokens = { bu = "sg", env = "p", region = "euw1", purpose = "k8s", instance = "01" }
  }

  expect_failures = [output.names]
}

run "the_iam_charset_accepts_characters_the_default_rejects" {
  command = plan

  # IAM names allow +=,.@_- ; a plain dashed name does not. The charset is per
  # resource type, which is the part of this module that is genuinely AWS-shaped.
  variables {
    overrides = { eks_role = "ng.p.euw1.eks.role.01" }
  }

  assert {
    condition     = output.names["eks_role"] == "ng.p.euw1.eks.role.01"
    error_message = "the iam charset rejected a name it should allow: ${output.names["eks_role"]}"
  }
}

run "the_same_name_fails_for_a_resource_with_the_dash_charset" {
  command = plan

  variables {
    overrides = { ecs_cluster = "ng.p.euw1.ecs.01" }
  }

  expect_failures = [output.names]
}

# ---------------------------------------------------------------------------
# Regression tests for the review findings carried over from #139.
# ---------------------------------------------------------------------------

run "an_over_length_generated_name_fails_the_plan" {
  command = plan

  # Names are not truncated to fit: doing so drops the trailing {type} and
  # {instance} segments, so two deployments differing only by instance collapse
  # onto one name — invisible to the duplicate check, since they are separate states.
  variables {
    tokens = {
      bu        = "verylongbusinessunitname"
      env       = "production"
      env_short = "pd"
      region    = "euwest1"
      purpose   = "analytics"
      instance  = "01"
    }
  }

  expect_failures = [output.names]
}

run "a_partial_resource_spec_keeps_the_built_in_attributes" {
  command = plan

  # Changing only the abbreviation must not reset the rest of the spec. A whole-object
  # merge reset max_length to the variable default, so an over-long IAM role name
  # passed the plan and was rejected by AWS at 64.
  variables {
    resource_specs = {
      eks_role       = { type = "iamrole" }
      staging_bucket = { type = "bkt" }
    }
  }

  assert {
    condition     = output.names["eks_role"] == "ng-p-euw1-eks-iamrole-01"
    error_message = "eks_role was ${output.names["eks_role"]}"
  }

  # lower = true and charset = lowerdot must survive an override mentioning neither.
  assert {
    condition     = output.names["staging_bucket"] == "ng-p-euw1-staging-bkt-01"
    error_message = "staging_bucket lost its spec: ${output.names["staging_bucket"]}"
  }
}

run "an_underscore_format_does_not_come_back_with_mixed_separators" {
  command = plan

  # An empty-token gap used to collapse to a hyphen regardless of the separator the
  # format uses, so an underscore form came back mixed. Applied to ecs_task_family,
  # whose charset permits underscores — unlike the dash default, which is why this is
  # a per-key form rather than a global override on AWS.
  variables {
    formats = { underscore = "{bu}_{env}_{region}_{purpose}_{type}_{instance}" }
    tokens  = { bu = "ng", env = "p", region = "euw1", instance = "01" }
    resource_specs = {
      ecs_task_family = { form = "underscore" }
    }
  }

  assert {
    condition     = output.names["ecs_task_family"] == "ng_p_euw1_ecstask_01"
    error_message = "expected underscores throughout, got ${output.names["ecs_task_family"]}"
  }

  # The default-form keys are untouched and still hyphenated.
  assert {
    condition     = output.names["ecs_cluster"] == "ng-p-euw1-ecs-01"
    error_message = "ecs_cluster was ${output.names["ecs_cluster"]}"
  }
}
