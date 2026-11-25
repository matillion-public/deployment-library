# Run with: terraform test  (from modules/azure/aks)
#
# The namespace reaches the subject of both federated credentials, which must
# equal the namespace the chart is installed into. Uses mock providers, so no
# Azure credentials or resources are needed.

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

variables {
  name                 = "t"
  location             = "uksouth"
  resource_group_name  = "rg"
  subnet_ids           = ["/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/aks"]
  tags                 = {}
  random_string_salt   = "abc123"
  authorized_ip_ranges = ["203.0.113.0/24"]
}

run "default_namespace_is_matillion" {
  command = plan

  assert {
    condition     = azurerm_federated_identity_credential.runner_federated_credential[0].subject == "system:serviceaccount:matillion:matillion-runner-sa"
    error_message = "The runner federated credential should be bound to the matillion namespace by default."
  }

  assert {
    condition     = azurerm_federated_identity_credential.script_runner_federated_credential[0].subject == "system:serviceaccount:matillion:matillion-runner-script-runner-sa"
    error_message = "The script runner federated credential should be bound to the matillion namespace by default."
  }
}

run "namespace_reaches_both_federated_credentials" {
  command = plan

  variables {
    namespace = "finance"
  }

  assert {
    condition     = startswith(azurerm_federated_identity_credential.runner_federated_credential[0].subject, "system:serviceaccount:finance:")
    error_message = "The runner federated credential should be bound to the namespace variable."
  }

  assert {
    condition     = startswith(azurerm_federated_identity_credential.script_runner_federated_credential[0].subject, "system:serviceaccount:finance:")
    error_message = "The script runner federated credential should be bound to the namespace variable."
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

run "hyphenated_63_character_namespace_is_accepted" {
  command = plan

  variables {
    namespace = "team-a-23456789012345678901234567890123456789012345678901234567"
  }

  assert {
    condition     = startswith(azurerm_federated_identity_credential.runner_federated_credential[0].subject, "system:serviceaccount:team-a-")
    error_message = "A 63-character namespace with hyphens is valid and should be accepted."
  }
}
