# modules/core/networking-vnet  (Azure)
#
# References the existing VNet + subnet the agent deploys into (bring-your-own)
# and emits the least-privilege permission set the composer contract declares.
# See core/networking-vpc for the AWS/GCP equivalent.

resource "azurerm_role_definition" "deployer" {
  count       = var.create_deployer_role ? 1 : 0
  name        = "${var.deployment_name}-networking-vnet-deployer"
  scope       = var.role_scope
  description = "Least-privilege permissions to provision the core/networking-vnet module."

  permissions {
    actions = [
      "Microsoft.Network/virtualNetworks/read",
      "Microsoft.Network/virtualNetworks/subnets/read",
    ]
    not_actions = []
  }

  assignable_scopes = [var.role_scope]
}
