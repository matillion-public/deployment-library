# Calls the module with a Key Vault name nobody knows until apply, as when a caller
# passes module.aks.key_vault_name from the same apply. A random suffix with no
# known prefix stands in for it, so the name is wholly unknown at plan.

resource "random_string" "vault_name" {
  length  = 6
  special = false
  upper   = false
}

module "identity" {
  source = "../.."

  name                          = "finance"
  location                      = "uksouth"
  resource_group_name           = "platform"
  oidc_issuer_url               = "https://uksouth.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/11111111-1111-1111-1111-111111111111/"
  namespace                     = "finance"
  service_account_name          = "finance-sa"
  key_vault_name                = random_string.vault_name.result
  key_vault_resource_group_name = "platform"
  grant_vault_wide_secret_write = true
}

output "access_model" {
  value = module.identity.access_model
}
