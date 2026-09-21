# core/networking-vnet (Azure)

References the existing VNet + subnet the agent deploys into (bring-your-own) and
emits the least-privilege permission set the composer contract declares:
`Microsoft.Network/virtualNetworks/read`,
`Microsoft.Network/virtualNetworks/subnets/read`.

> AWS/GCP use the shared [`core/networking-vpc`](../networking-vpc) path.

## Inputs
`deployment_name`, `vnet_name` *(required)*, `subnet_name` *(required)*,
`role_scope` *(required)*, `create_deployer_role`.

## Outputs
`vnet_name`, `subnet_name`, `deployer_role_definition_id`.
