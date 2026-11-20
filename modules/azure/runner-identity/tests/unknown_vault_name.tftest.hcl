# Run with: terraform test  (from modules/azure/runner-identity)
#
# A caller that creates the vault in the same apply can't know its name at plan.
# Nothing that decides how many resources to create may depend on it. Uses a mock
# provider, so no Azure credentials or resources are needed.

mock_provider "azurerm" {
  mock_data "azurerm_key_vault" {
    defaults = { rbac_authorization_enabled = true }
  }
}

run "plans_before_the_vault_name_is_known" {
  command = plan

  module {
    source = "./tests/unknown-vault-name"
  }

  assert {
    condition     = output.access_model == "vault-read-write"
    error_message = "The identity must get write on the vault even before the vault's name is known."
  }
}
