# Run with: terraform test  (from runner/azure/aks)
#
# The network policy inputs reach the cluster through this root. The assertions
# read module.aks outputs because a root test cannot read resources inside a
# child module. Uses mock providers, so no Azure credentials or resources are
# needed.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      subscription_id = "00000000-0000-0000-0000-000000000002"
      object_id       = "00000000-0000-0000-0000-000000000003"
    }
  }
}

mock_provider "azuread" {}

mock_provider "http" {
  mock_data "http" {
    defaults = { response_body = "198.51.100.7" }
  }
}

override_resource {
  target          = random_string.salt
  override_during = plan
  values          = { result = "abc123" }
}

variables {
  name                  = "t"
  azure_subscription_id = "00000000-0000-0000-0000-000000000002"
  azure_tenant_id       = "00000000-0000-0000-0000-000000000001"
  location              = "uksouth"
  resource_group_name   = "rg"
  tags                  = {}
  authorized_ip_ranges  = ["203.0.113.0/24"]
}

# network_policy is not asserted here: the provider computes it when unset, so
# its value is unknown at plan.
run "defaults_install_no_engine" {
  command = plan

  assert {
    condition     = module.aks.network_data_plane == "azure"
    error_message = "network_data_plane must default to azure."
  }

  assert {
    condition     = module.aks.network_plugin_mode == null
    error_message = "network_plugin_mode must default to node-subnet mode."
  }
}

run "cilium_is_passed_through" {
  command = plan

  variables {
    network_plugin_mode = "overlay"
    network_policy      = "cilium"
    network_data_plane  = "cilium"
  }

  assert {
    condition     = module.aks.network_plugin_mode == "overlay"
    error_message = "network_plugin_mode should be overlay."
  }

  assert {
    condition     = module.aks.network_policy == "cilium"
    error_message = "network_policy should be cilium."
  }

  assert {
    condition     = module.aks.network_data_plane == "cilium"
    error_message = "network_data_plane should be cilium."
  }
}

run "calico_on_azure_data_plane" {
  command = plan

  variables {
    network_policy = "calico"
  }

  assert {
    condition     = module.aks.network_policy == "calico"
    error_message = "network_policy should be calico."
  }

  assert {
    condition     = module.aks.network_data_plane == "azure"
    error_message = "Calico runs on the azure data plane."
  }
}

run "rejects_unknown_policy_engine" {
  command = plan

  variables {
    network_policy = "none"
  }

  expect_failures = [var.network_policy]
}

run "rejects_unknown_data_plane" {
  command = plan

  variables {
    network_data_plane = "kubenet"
  }

  expect_failures = [var.network_data_plane]
}

run "rejects_unknown_plugin_mode" {
  command = plan

  variables {
    network_plugin_mode = "dynamic"
  }

  expect_failures = [var.network_plugin_mode]
}
