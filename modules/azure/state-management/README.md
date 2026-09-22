# Azure Terraform state management

Creates the resource group, storage account and blob container that hold Terraform
state for a deployment. This is a bootstrap module: it runs with local state, and
everything else then uses the backend it created.

```hcl
module "state_management" {
  source = "../../modules/azure/state-management"

  account_id             = var.account_id
  resource_group_prefix  = var.resource_group_prefix
  location               = var.location
  principal_ids          = [data.azurerm_client_config.current.object_id]
}
```

## The names are a contract, not a cosmetic choice

All three names are also backend configuration. A Terraform backend is resolved
before any provider runs, so it cannot read them from this module at `init` time —
they have to be written into the backend block.

Take them from the `backend_config` output rather than typing them:

```hcl
output "backend_config" {
  value = {
    resource_group_name  = ...
    storage_account_name = ...
    container_name       = ...
  }
}
```

`templates/backend_azurerm.tf.tmpl` renders all three from that output. None of them
is hardcoded in the template, so a `resource_names` override cannot leave the backend
pointing at something that does not exist.

## Renaming a deployed backend is a state migration

`name` is force-new on all three resources, and the container holds every state blob
for the deployment. Changing `resource_names.state_container`,
`state_storage_account` or `state_resource_group` on a **live** platform is therefore
not a rename — it is "create a new empty backend and abandon the old one".

The storage account and the container both carry `prevent_destroy`, so a plan that
would replace them fails rather than proceeding. That is deliberate: the failure is
much cheaper than the alternative. To migrate on purpose:

1. `terraform state pull` from the existing backend and keep the file.
2. Remove the `prevent_destroy` blocks.
3. Apply the new names.
4. `terraform state push` into the new container, or re-`init -migrate-state`.

To tear the backend down entirely, remove the `prevent_destroy` blocks first.

## Naming keys

Consumed from `modules/azure/naming` (see its README):

| Key | Resource | Azure limit |
|---|---|---|
| `state_resource_group` | resource group | 90 |
| `state_storage_account` | storage account — globally unique, dashless, lowercase | 24 |
| `state_container` | blob container | 63 |

Leave `resource_names` unset and the module derives all three from `account_id` and
`resource_group_prefix`, exactly as it did before naming existed.
