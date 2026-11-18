# Run with: terraform test  (from runner/azure/aks-existing-cluster)
#
# The first real plan, with no override on the Key Vault's random suffix, so its name
# isn't known yet. Nothing that decides how many resources to create may depend on
# it. The mock provider keeps the name's known "finance-" prefix, which the real one
# drops, so modules/azure/runner-identity/tests/unknown_vault_name.tftest.hcl is the
# test that reproduces a wholly unknown name. Uses a mock provider, so no Azure
# credentials or resources are needed.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000000"
      subscription_id = "11111111-1111-1111-1111-111111111111"
    }
  }
  mock_data "azurerm_kubernetes_cluster" {
    defaults = {
      location            = "uksouth"
      oidc_issuer_enabled = true
      oidc_issuer_url     = "https://uksouth.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/22222222-2222-2222-2222-222222222222/"
    }
  }
  mock_data "azurerm_key_vault" {
    defaults = { rbac_authorization_enabled = true }
  }
}

variables {
  name                        = "finance"
  azure_subscription_id       = "11111111-1111-1111-1111-111111111111"
  cluster_name                = "platform-shared"
  cluster_resource_group_name = "platform-rg"
}

run "plans_before_the_vault_name_is_known" {
  command = plan

  assert {
    condition     = module.identity.access_model == "vault-read-write" && module.script_runner_identity.access_model == "none"
    error_message = "The runner must get write on its vault and the script runner no vault, even before the vault's name is known."
  }
}
