# Run with: terraform test  (from modules/azure/naming)

variables {
  tokens = {
    bu        = "ng"
    env       = "p"
    env_short = "pd"
    region    = "eus2"
    purpose   = "runner"
    instance  = "01"
  }
}

run "dashed_names_follow_the_convention" {
  command = plan

  assert {
    condition     = output.names["vnet"] == "ng-p-eus2-runner-vnet-01"
    error_message = "vnet was ${output.names["vnet"]}"
  }

  assert {
    condition     = output.names["nat_gateway"] == "ng-p-eus2-runner-natgw-01"
    error_message = "nat_gateway was ${output.names["nat_gateway"]}"
  }
}

run "storage_account_is_dashless_lowercase_and_capped" {
  command = plan

  assert {
    condition     = output.names["storage_account"] == "ngpdeus2runnerst01"
    error_message = "storage_account was ${output.names["storage_account"]}"
  }

  assert {
    condition     = length(output.names["storage_account"]) <= 24
    error_message = "storage_account exceeds the 24 character limit"
  }
}

run "empty_tokens_do_not_leave_dangling_separators" {
  command = plan

  variables {
    tokens = { bu = "ng", env = "p", region = "eus2" }
  }

  assert {
    condition     = output.names["vnet"] == "ng-p-eus2-vnet"
    error_message = "expected no gap where purpose and instance would be, got ${output.names["vnet"]}"
  }
}

run "explicit_override_wins" {
  command = plan

  variables {
    overrides = { vnet = "legacy-vnet-name" }
  }

  assert {
    condition     = output.names["vnet"] == "legacy-vnet-name"
    error_message = "override was not applied, got ${output.names["vnet"]}"
  }

  assert {
    condition     = output.names["nsg"] == "ng-p-eus2-runner-nsg-01"
    error_message = "override leaked into other keys"
  }
}

run "custom_format_and_abbreviation" {
  command = plan

  variables {
    formats        = { dashed = "lz{bu}-{env}-{region}-{purpose}-{type}-{instance}" }
    resource_specs = { subnet = { type = "snet", form = "dashed", max_length = 80 } }
  }

  assert {
    condition     = output.names["subnet"] == "lzng-p-eus2-runner-snet-01"
    error_message = "custom format not applied, got ${output.names["subnet"]}"
  }
}

run "name_over_the_azure_limit_fails_the_plan" {
  command = plan

  variables {
    overrides = { key_vault = "this-key-vault-name-is-far-too-long-for-azure" }
  }

  expect_failures = [output.names]
}

run "identities_that_share_an_abbreviation_get_distinct_names" {
  command = plan

  # Every managed identity abbreviates to "id", so the per-key purpose is what
  # keeps them apart. Both are wired in the aks module, so a collision here would
  # surface as a duplicate resource name on apply.
  assert {
    condition     = output.names["aks_identity"] != output.names["runner_identity"]
    error_message = "aks_identity and runner_identity both resolved to ${output.names["aks_identity"]}"
  }

  assert {
    condition     = output.names["aks_identity"] == "ng-p-eus2-aks-id-01"
    error_message = "aks_identity was ${output.names["aks_identity"]}"
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
      aks_identity    = { type = "id", form = "dashed", max_length = 128, purpose = "shared" }
      runner_identity = { type = "id", form = "dashed", max_length = 128, purpose = "shared" }
    }
  }

  expect_failures = [output.names]
}

run "storage_container_keeps_its_hyphens" {
  command = plan

  # Lowercase and separator-free are different constraints: containers are the
  # first, storage accounts are both.
  assert {
    condition     = output.names["state_container"] == "ng-p-eus2-tfstate-stct-01"
    error_message = "state_container was ${output.names["state_container"]}"
  }
}

# ---------------------------------------------------------------------------
# Regression tests for the review findings on this PR.
# ---------------------------------------------------------------------------

run "an_over_length_generated_name_fails_the_plan" {
  command = plan

  # Previously the name was truncated to max_length *before* the length check, so
  # the check could never fire for a generated name. Truncation also cut off
  # {type} and {instance}, meaning instance 01 and 02 produced the same 24-character
  # storage account name — a global collision that surfaces at apply, in a separate
  # state where the duplicate check cannot see it.
  variables {
    tokens = {
      bu        = "contoso"
      env       = "prod"
      env_short = "pd"
      region    = "eastus2"
      purpose   = "analytics"
      instance  = "01"
    }
  }

  expect_failures = [output.names]
}

run "a_partial_resource_spec_keeps_the_built_in_attributes" {
  command = plan

  # Changing only the abbreviation is the README's advertised use case. A whole-object
  # merge would reset max_length to the variable default, so this name would pass the
  # plan at 34 characters and then be rejected by Azure at 24.
  variables {
    resource_specs = {
      key_vault       = { type = "akv" }
      storage_account = { type = "sa" }
    }
  }

  assert {
    condition     = output.names["key_vault"] == "ng-p-eus2-runner-akv-01"
    error_message = "key_vault was ${output.names["key_vault"]}"
  }

  # form = dashless and lower = true must survive an override that mentions neither.
  assert {
    condition     = output.names["storage_account"] == "ngpdeus2runnersa01"
    error_message = "storage_account lost its dashless/lower spec: ${output.names["storage_account"]}"
  }
}

run "an_underscore_format_does_not_come_back_with_mixed_separators" {
  command = plan

  # formats is an advertised override point. Collapsing an empty-token gap always to
  # a hyphen produced ng_p_eus2-vnet_01.
  variables {
    formats = { dashed = "{bu}_{env}_{region}_{purpose}_{type}_{instance}" }
    tokens  = { bu = "ng", env = "p", region = "eus2", instance = "01" }
  }

  assert {
    condition     = output.names["vnet"] == "ng_p_eus2_vnet_01"
    error_message = "expected underscores throughout, got ${output.names["vnet"]}"
  }
}

run "each_identity_and_credential_has_its_own_key" {
  command = plan

  # aks, container-apps and runner-identity each create their own identity, and
  # runner-identity can be composed alongside aks. One shared key across three
  # resources generated one name for all of them; the duplicate check compares key
  # against key, so it could not see it.
  assert {
    condition = length(distinct([
      output.names["runner_identity"],
      output.names["script_runner_identity"],
      output.names["tenant_runner_identity"],
      output.names["container_app_identity"],
      output.names["aks_identity"],
      output.names["queue_adapter_identity"],
    ])) == 6
    error_message = "two managed identities resolved to the same name"
  }

  assert {
    condition = length(distinct([
      output.names["runner_federated_credential"],
      output.names["script_runner_federated_credential"],
      output.names["tenant_runner_federated_credential"],
      output.names["tenant_script_runner_federated_credential"],
    ])) == 4
    error_message = "two federated credentials resolved to the same name"
  }
}

run "keys_with_no_consuming_resource_are_not_generated" {
  command = plan

  # subnet, resource_group, keda_federated_credential and
  # queue_adapter_federated_credential were generated and validated but never read
  # by any resource, so an override on them was silently dropped.
  assert {
    condition = length([
      for k in ["subnet", "resource_group", "keda_federated_credential", "queue_adapter_federated_credential"] :
      k if contains(keys(output.names), k)
    ]) == 0
    error_message = "a key with no consuming resource is still in the names map"
  }
}
