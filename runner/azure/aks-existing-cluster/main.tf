# A Matillion runner in an AKS cluster that already exists, beside any other runners
# in it. Nothing here changes the cluster or creates anything in it. This creates the
# runner's managed identities and Key Vault, each identity bound to a service
# account name in the runner's namespace; the runner chart, installed with Helm,
# creates that namespace and those service accounts. README.md shows the install,
# and how to add the namespace to the cluster's Prometheus.

data "azurerm_client_config" "current" {}

data "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  resource_group_name = var.cluster_resource_group_name

  lifecycle {
    # Federated credentials trust the cluster's OIDC issuer. Without one there is
    # nothing to trust, and pods never get an Azure token. The workload identity
    # addon is the other half of that, but azurerm doesn't report it: README.md
    # lists it as a prerequisite.
    postcondition {
      condition     = self.oidc_issuer_enabled && self.oidc_issuer_url != ""
      error_message = "AKS cluster '${var.cluster_name}' has no OIDC issuer, so the runner's federated credentials would trust nothing and its pods would get no Azure token. Enable it, with workload identity, once per cluster: az aks update --resource-group ${var.cluster_resource_group_name} --name ${var.cluster_name} --enable-oidc-issuer --enable-workload-identity"
    }
  }
}

locals {
  namespace                          = var.name
  service_account_name               = "${var.name}-sa"
  script_runner_service_account_name = "${var.name}-script-runner-sa"
  resource_group_name                = coalesce(var.resource_group_name, var.cluster_resource_group_name)
  location                           = data.azurerm_kubernetes_cluster.this.location

  # Key Vault names are unique across Azure, 3 to 24 characters, and take letters,
  # digits and single hyphens. Up to 17 characters of the runner's name, with runs of
  # hyphens collapsed and none left at the end, then a hyphen and 6 random characters.
  key_vault_name = "${trimsuffix(substr(replace(var.name, "/-+/", "-"), 0, 17), "-")}-${random_string.key_vault_suffix.result}"
}

resource "random_string" "key_vault_suffix" {
  length  = 6
  special = false
  upper   = false
}

# The runner's own vault. Azure RBAC can't limit a role to secrets whose names start
# with a prefix, so the vault is the boundary between runners. Whoever runs Terraform
# gets no role on it: nothing here reads or writes a secret, and the runner saves
# its own.
resource "azurerm_key_vault" "runner" {
  # checkov:skip=CKV_AZURE_109:The runner reaches the vault from the cluster's egress, which this root doesn't own. Restrict it with the cluster's network rules or a private endpoint.
  # checkov:skip=CKV_AZURE_189:As above: closing public access needs a private endpoint in the cluster's network, which belongs to whoever runs the cluster.
  # checkov:skip=CKV2_AZURE_32:As above.
  name                       = local.key_vault_name
  location                   = local.location
  resource_group_name        = local.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  # The runner can delete secrets (no narrower built-in role lets it write them), so
  # anything deleted, by it or anyone, stays recoverable for the retention period.
  # Purge protection can't be turned off once on, and a destroyed vault keeps its
  # name until the retention period ends.
  purge_protection_enabled = true
  tags                     = var.tags
}

module "identity" {
  source = "../../../modules/azure/runner-identity"

  name                          = var.name
  location                      = local.location
  resource_group_name           = local.resource_group_name
  oidc_issuer_url               = data.azurerm_kubernetes_cluster.this.oidc_issuer_url
  namespace                     = local.namespace
  service_account_name          = local.service_account_name
  key_vault_name                = azurerm_key_vault.runner.name
  key_vault_resource_group_name = azurerm_key_vault.runner.resource_group_name
  grant_vault_wide_secret_write = true
  storage_account_ids           = var.storage_account_ids
  grant_storage_account_keys    = var.grant_storage_account_keys
  tags                          = var.tags
}

# The script runner runs code people write, so it gets an identity of its own: blob
# access to the same storage accounts, and no Key Vault or account keys. With the
# runner's identity, a script could read and overwrite every secret the runner keeps,
# OAuth tokens included, and take away account keys that outlive the pod.
module "script_runner_identity" {
  source = "../../../modules/azure/runner-identity"

  name                   = "${var.name}-scripts"
  location               = local.location
  resource_group_name    = local.resource_group_name
  oidc_issuer_url        = data.azurerm_kubernetes_cluster.this.oidc_issuer_url
  namespace              = local.namespace
  service_account_name   = local.script_runner_service_account_name
  grant_key_vault_access = false
  storage_account_ids    = var.storage_account_ids
  tags                   = var.tags
}
