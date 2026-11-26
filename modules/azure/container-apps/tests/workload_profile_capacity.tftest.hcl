# Run with: terraform test  (from modules/azure/container-apps)
#
# The workload profile must hold replica_count runner replicas, plus the script
# runner replica when enable_script_runner = true, on at most
# workload_profile_max_count instances. Plan fails when the requested vCPU is
# more than workload_profile_max_count times the vCPU of a D- or E-series
# profile type; other profile types are not checked. Uses a mock provider, so
# no Azure credentials are needed.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      object_id       = "00000000-0000-0000-0000-000000000002"
      subscription_id = "00000000-0000-0000-0000-000000000003"
    }
  }
}

variables {
  name                   = "t"
  location               = "uksouth"
  resource_group_name    = "rg-test"
  random_string_salt     = "abc123"
  subnet_ids             = ["/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/apps"]
  account_id             = "12345"
  agent_id               = "00000000-0000-0000-0000-000000000004"
  client_id              = "client-id"
  client_secret          = "client-secret"
  matillion_cloud_region = "eu1"
}

run "default_configuration_fits" {
  command = plan
}

run "large_two_replicas_one_instance_fails" {
  command = plan

  variables {
    runner_size = "large"
  }

  expect_failures = [azurerm_container_app.app]
}

run "large_two_replicas_two_instances_fits" {
  command = plan

  variables {
    runner_size                = "large"
    workload_profile_max_count = 2
  }
}

run "medium_two_replicas_one_instance_is_not_rejected" {
  command = plan

  variables {
    runner_size = "medium"
  }
}

run "xlarge_two_replicas_one_instance_fails" {
  command = plan

  variables {
    runner_size = "xlarge"
  }

  expect_failures = [azurerm_container_app.app]
}

run "script_runner_counts_against_capacity" {
  command = plan

  variables {
    runner_size                   = "large"
    replica_count                 = 1
    enable_script_runner          = true
    script_runner_authorized_keys = "ssh-ed25519 AAAA test"
  }

  expect_failures = [azurerm_container_app.app]
}

run "e_series_override_fits" {
  command = plan

  variables {
    workload_profile_type = "E4"
    container_cpu         = "1.0"
    container_memory      = "8Gi"
  }
}

run "unparsed_profile_type_is_not_checked" {
  command = plan

  variables {
    runner_size           = "large"
    workload_profile_type = "NC24-A100"
  }
}
