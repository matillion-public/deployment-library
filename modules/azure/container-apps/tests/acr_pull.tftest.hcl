# Run with: terraform test  (from modules/azure/container-apps)
#
# The runner identity gets AcrPull only when container_acr_id names a private
# registry, and then only on that registry. The default public image pulls
# anonymously, so no AcrPull role is assigned. Uses a mock provider, so no
# Azure credentials are needed.

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

run "acr_pull_not_created_by_default" {
  command = plan

  assert {
    condition     = length(azurerm_role_assignment.acr_pull) == 0
    error_message = "With container_acr_id unset (the default public image) the runner identity must not be assigned AcrPull."
  }
}

run "acr_pull_scoped_to_registry_when_set" {
  command = plan

  variables {
    container_image_url = "privateacr.azurecr.io/cloud-agent:current"
    container_acr_id    = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-acr/providers/Microsoft.ContainerRegistry/registries/privateacr"
  }

  assert {
    condition     = length(azurerm_role_assignment.acr_pull) == 1
    error_message = "With container_acr_id set the runner identity must get exactly one AcrPull assignment."
  }

  assert {
    condition     = azurerm_role_assignment.acr_pull[0].scope == var.container_acr_id
    error_message = "The AcrPull assignment must be scoped to the registry named by container_acr_id."
  }

  assert {
    condition     = azurerm_role_assignment.acr_pull[0].role_definition_name == "AcrPull"
    error_message = "The assignment must use the AcrPull role."
  }
}
