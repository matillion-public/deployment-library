# Run with: terraform test  (from runner/azure/aks)
#
# The namespace input reaches the federated credentials through this root. The
# assertions read module.aks outputs because a root test cannot read resources
# inside a child module. Uses mock providers, so no Azure credentials or
# resources are needed.

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

run "default_namespace_is_matillion" {
  command = plan

  assert {
    condition     = module.aks.runner_federated_credential_subject == "system:serviceaccount:matillion:matillion-runner-sa"
    error_message = "The root should bind the runner federated credential to the matillion namespace by default."
  }
}

run "namespace_is_passed_to_the_module" {
  command = plan

  variables {
    namespace = "finance"
  }

  assert {
    condition     = module.aks.runner_federated_credential_subject == "system:serviceaccount:finance:matillion-runner-sa"
    error_message = "The root should pass the namespace variable to the module."
  }
}

run "uppercase_namespace_is_rejected" {
  command = plan

  variables {
    namespace = "Matillion"
  }

  expect_failures = [var.namespace]
}

run "underscore_namespace_is_rejected" {
  command = plan

  variables {
    namespace = "team_a"
  }

  expect_failures = [var.namespace]
}

run "namespace_over_63_characters_is_rejected" {
  command = plan

  variables {
    namespace = "a234567890123456789012345678901234567890123456789012345678901234"
  }

  expect_failures = [var.namespace]
}
