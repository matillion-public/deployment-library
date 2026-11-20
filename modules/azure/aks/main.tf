# Data source to get the current Azure client configuration
data "azurerm_client_config" "current" {}

data "http" "terraform_runner_external_ip" {
  url = "https://ipv4.icanhazip.com"
}

# User Assigned Managed Identity
resource "azurerm_user_assigned_identity" "aks_identity" {
  name                = lookup(var.resource_names, "aks_identity", join("-", [var.name, "aks-identity", var.random_string_salt]))
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# Azure Kubernetes Service (AKS) Cluster
locals {
  # Default the floor to one node per zone so zone spread is real at rest, and to
  # 2 when the pool is zone-unaware (a floor of 1 permits no voluntary eviction).
  min_node_count = coalesce(var.min_node_count, max(2, length(var.node_pool_zones)))

  # Default the ceiling to double the desired size. Raising desired_node_count
  # raises the floor with it, so headroom is the cheaper dial of the two.
  max_node_count = coalesce(var.max_node_count, var.desired_node_count * 2)

  # The shared runner identity needs the cluster's OIDC issuer, but the issuer
  # does not need it: a shared cluster federates per-tenant identities instead.
  create_runner_identity = var.workload_identity_enabled && var.create_runner_identity

  # Key Vault names are limited to 24 characters. The default is the base name, a
  # hyphen and the salt, cut at 24, so a long base name loses salt characters.
  key_vault_name = lookup(var.resource_names, "key_vault", substr(join("-", [var.name, var.random_string_salt]), 0, 24))

  # The salt is unknown at plan on a new deployment, so the Key Vault name checks
  # read only var.name and assume the root's 6-character alphanumeric salt.
  key_vault_salt_length         = 6
  key_vault_name_without_salt   = substr("${var.name}-", 0, 24)
  key_vault_name_keeps_salt     = length(var.name) + 1 + local.key_vault_salt_length <= 24
  key_vault_name_ends_in_hyphen = length(var.name) >= 23 && endswith(local.key_vault_name_without_salt, "-")
}

resource "azurerm_kubernetes_cluster" "aks_cluster" {
  # Cost analysis needs Standard or Premium: on Free the addon cannot be enabled,
  # so per-namespace and per-deployment spend never reaches Cost Management. Free
  # also carries no uptime SLA.
  sku_tier = var.sku_tier

  name                = lookup(var.resource_names, "aks_cluster", join("-", [var.name, "aks-cluster", var.random_string_salt]))
  location            = var.location
  resource_group_name = var.resource_group_name

  dynamic "api_server_access_profile" {
    for_each = var.is_private_cluster ? [] : [1]
    content {
      authorized_ip_ranges = concat(
        var.authorized_ip_ranges,
        [join("", [trimspace(data.http.terraform_runner_external_ip.response_body), "/32"])],
        var.nat_gateway_public_ip != null ? [join("", [var.nat_gateway_public_ip, "/32"])] : [],
      )
    }
  }

  default_node_pool {
    name                 = "agentpool2"
    vm_size              = var.vm_size
    os_disk_size_gb      = var.node_disk_size
    auto_scaling_enabled = true
    # The floor has to cover every zone the pool spans, or a zone-spread workload
    # silently has no zone redundancy at the floor: two nodes cover two of three
    # zones, and topologySpread degrades quietly rather than leaving pods Pending.
    min_count = local.min_node_count
    # Headroom in proportion to the pool rather than a flat +2. On a shared cluster
    # several tenants can scale at once — each runner's HPA plus each queue
    # adapter's ScaledJob — and a pool that only grows by two nodes leaves pods
    # Pending, which reads as the platform being slow rather than out of capacity.
    max_count      = local.max_node_count
    node_count     = var.desired_node_count
    vnet_subnet_id = var.subnet_ids[0]
    # Empty list leaves the pool zone-unaware, which is what existing clusters
    # already have. Node pool zones are immutable in Azure, so populating this
    # on a live cluster forces the pool to be replaced.
    zones = var.node_pool_zones
    # AKS sets max_surge on the pool when none is given. For drain and soak it
    # returns no value and the provider records 0. Leaving the block out plans a
    # removal of all three after every apply.
    upgrade_settings {
      max_surge                     = "10%"
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks_identity.id]
  }

  network_profile {
    network_plugin = "azure"
    # Null is node-subnet mode, which is what existing clusters run: every pod
    # takes a VNet address. Overlay moves pods onto pod_cidr instead.
    network_plugin_mode = var.network_plugin_mode
    pod_cidr            = var.pod_cidr
    load_balancer_sku   = "standard"
    service_cidr        = "10.2.0.0/16"
    dns_service_ip      = "10.2.0.10"
    outbound_type       = var.enable_nat_gateway ? "userAssignedNATGateway" : "loadBalancer"
    # Null installs no policy engine and azure is the provider's own default
    # data plane, which together are what existing clusters run.
    network_policy     = var.network_policy
    network_data_plane = var.network_data_plane
  }

  local_account_disabled = var.local_account_disabled

  # Absent by default, which is what existing clusters have. The provider
  # (4.x) has no `managed` argument: Entra integration is always the managed kind.
  dynamic "azure_active_directory_role_based_access_control" {
    for_each = var.azure_rbac_enabled ? [1] : []
    content {
      azure_rbac_enabled     = true
      admin_group_object_ids = var.admin_group_object_ids
    }
  }

  dynamic "oms_agent" {
    for_each = var.enable_container_insights ? [1] : []
    content {
      log_analytics_workspace_id = azurerm_log_analytics_workspace.aks_log_workspace[0].id
    }
  }

  private_cluster_enabled = var.is_private_cluster

  dns_prefix = join("-", [var.name, "aks", var.random_string_salt])

  oidc_issuer_enabled       = var.workload_identity_enabled
  workload_identity_enabled = var.workload_identity_enabled

  tags = var.tags

  lifecycle {
    precondition {
      condition     = !var.local_account_disabled || var.azure_rbac_enabled
      error_message = "local_account_disabled = true requires azure_rbac_enabled = true. With local accounts off and no Entra integration, no identity could authenticate to the cluster."
    }

    precondition {
      condition     = var.azure_rbac_enabled || length(var.admin_group_object_ids) == 0
      error_message = "admin_group_object_ids only takes effect with azure_rbac_enabled = true. Set azure_rbac_enabled = true or leave admin_group_object_ids empty."
    }

    precondition {
      condition     = var.pod_cidr == null || var.network_plugin_mode == "overlay"
      error_message = "pod_cidr only applies with network_plugin_mode = \"overlay\". In node-subnet mode pods take their addresses from the node subnet, and Azure rejects a pod CIDR."
    }

    # Cilium is one choice made in two places: the Cilium data plane enforces
    # policy only through Cilium, and Cilium policy needs the Cilium data plane.
    precondition {
      condition     = (var.network_policy == "cilium") == (var.network_data_plane == "cilium")
      error_message = "network_policy = \"cilium\" and network_data_plane = \"cilium\" must be set together. The Cilium data plane cannot run Azure NPM or Calico, and Cilium policy cannot run on the Azure data plane."
    }

    # Azure requires the Cilium data plane to run on overlay or a dedicated pod
    # subnet; this module offers overlay only.
    precondition {
      condition     = var.network_data_plane != "cilium" || var.network_plugin_mode == "overlay"
      error_message = "network_data_plane = \"cilium\" requires network_plugin_mode = \"overlay\". Azure does not run the Cilium data plane in node-subnet mode."
    }

    # The azurerm provider rejects a node_count below min_count when auto scaling is
    # on, but only while expanding the resource at apply, after the rest of the
    # root has been created.
    precondition {
      condition     = var.desired_node_count >= local.min_node_count
      error_message = "desired_node_count (${var.desired_node_count}) must be at least the autoscaler floor (${local.min_node_count}). The floor defaults to one node per zone in node_pool_zones, or 2 when the pool is zone-unaware. Raise desired_node_count, or set min_node_count lower."
    }
  }
}

# Log Analytics for AKS Logs
resource "azurerm_log_analytics_workspace" "aks_log_workspace" {
  count = var.enable_container_insights ? 1 : 0

  name                = lookup(var.resource_names, "log_workspace", join("-", [var.name, "log-workspace", var.random_string_salt]))
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"

  tags = var.tags
}

# The workspace used to be a single instance. Moving it to index 0 keeps an existing
# workspace in state when enable_container_insights is turned on, instead of
# destroying it and creating a new one under the same name.
moved {
  from = azurerm_log_analytics_workspace.aks_log_workspace
  to   = azurerm_log_analytics_workspace.aks_log_workspace[0]
}

# Blob Storage Account
resource "azurerm_storage_account" "stagging" {
  name                = lookup(var.resource_names, "storage_account", substr(lower(join("", ["stagging", var.random_string_salt])), 0, 24))
  resource_group_name = var.resource_group_name
  location            = var.location
  account_tier        = "Standard"
  # LRS keeps a single copy in one zone. Once the node pool spans zones via
  # node_pool_zones, staging storage is the remaining single-zone dependency, so
  # new deployments should set ZRS. The default stays LRS so existing state does
  # not move underneath anyone.
  account_replication_type        = var.storage_account_replication_type
  allow_nested_items_to_be_public = false

  tags = var.tags
}

# Key Vault
resource "azurerm_key_vault" "keyvault" {
  name                       = local.key_vault_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  enable_rbac_authorization  = true

  tags = var.tags

  lifecycle {
    precondition {
      condition     = contains(keys(var.resource_names), "key_vault") || !local.key_vault_name_ends_in_hyphen
      error_message = "The derived Key Vault name \"${local.key_vault_name_without_salt}\" ends in a hyphen, which Azure rejects. Shorten name to ${24 - 1 - local.key_vault_salt_length} characters or fewer so the name keeps the full salt, or set resource_names[\"key_vault\"]."
    }
  }
}

check "key_vault_name_keeps_full_salt" {
  assert {
    condition     = contains(keys(var.resource_names), "key_vault") || local.key_vault_name_keeps_salt
    error_message = "name is ${length(var.name)} characters, so the default Key Vault name keeps ${max(0, 24 - length(var.name) - 1)} of the ${local.key_vault_salt_length} salt characters. Vault names are global and soft-deleted vaults keep their names for 7 days, so fewer salt characters make a collision more likely. Keep name at ${24 - 1 - local.key_vault_salt_length} characters or fewer, or set resource_names[\"key_vault\"]."
  }
}

# Key Vault Administrator. With key_vault_administrator_principal_ids unset the
# identity running Terraform is the administrator, as before. When set, exactly
# the listed principals are administrators and the running identity is not granted.
resource "azurerm_role_assignment" "current_client_key_vault_admin" {
  count                = var.key_vault_administrator_principal_ids == null ? 1 : 0
  scope                = azurerm_key_vault.keyvault.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

moved {
  from = azurerm_role_assignment.current_client_key_vault_admin
  to   = azurerm_role_assignment.current_client_key_vault_admin[0]
}

resource "azurerm_role_assignment" "key_vault_administrators" {
  for_each             = var.key_vault_administrator_principal_ids == null ? toset([]) : var.key_vault_administrator_principal_ids
  scope                = azurerm_key_vault.keyvault.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = each.value

  # Azure rejects a second assignment with the same principal, role and scope.
  # This ordering destroys the current-client grant before a listed grant to the
  # same principal is created, and the reverse when the variable is unset.
  depends_on = [azurerm_role_assignment.current_client_key_vault_admin]
}

# Assign Storage Blob Data Contributor Role to Managed Identity
resource "azurerm_role_assignment" "blob_storage_role" {
  principal_id         = azurerm_user_assigned_identity.aks_identity.principal_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Storage Account Contributor"
  scope                = azurerm_storage_account.stagging.id
}

# Assign Key Vault Secrets User Role to Managed Identity
resource "azurerm_role_assignment" "key_vault_officer_role" {
  principal_id         = azurerm_user_assigned_identity.aks_identity.principal_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Key Vault Secrets Officer"
  scope                = azurerm_key_vault.keyvault.id
}

# Assign Key Vault Secrets User Role to Managed Identity
resource "azurerm_role_assignment" "key_vault_role" {
  principal_id         = azurerm_user_assigned_identity.aks_identity.principal_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Key Vault Secrets User"
  scope                = azurerm_key_vault.keyvault.id
}

# User Assigned Managed Identity for Runner Workload
resource "azurerm_user_assigned_identity" "runner_workload_identity" {
  count               = local.create_runner_identity ? 1 : 0
  name                = lookup(var.resource_names, "runner_identity", join("-", [var.name, "runner-workload-identity", var.random_string_salt]))
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# Assign Storage Blob Data Contributor Role to Runner Workload Identity
resource "azurerm_role_assignment" "runner_blob_storage_role" {
  count                = local.create_runner_identity ? 1 : 0
  principal_id         = azurerm_user_assigned_identity.runner_workload_identity[0].principal_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Storage Blob Data Contributor"
  scope                = azurerm_storage_account.stagging.id
}

# Assign Key Vault Secrets User Role to Runner Workload Identity
resource "azurerm_role_assignment" "runner_key_vault_role" {
  count                = local.create_runner_identity ? 1 : 0
  principal_id         = azurerm_user_assigned_identity.runner_workload_identity[0].principal_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Key Vault Secrets User"
  scope                = azurerm_key_vault.keyvault.id
}

# Assign Reader Role to Runner Workload Identity for Key Vault metadata
resource "azurerm_role_assignment" "runner_key_vault_reader_role" {
  count                = local.create_runner_identity ? 1 : 0
  principal_id         = azurerm_user_assigned_identity.runner_workload_identity[0].principal_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Reader"
  scope                = azurerm_key_vault.keyvault.id
}

# Assign Reader Role to Runner Workload Identity at Subscription level
# This allows az login --identity to list subscriptions and authenticate properly
resource "azurerm_role_assignment" "runner_subscription_reader_role" {
  count                = local.create_runner_identity ? 1 : 0
  principal_id         = azurerm_user_assigned_identity.runner_workload_identity[0].principal_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Reader"
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
}

# Federated Identity Credential for Runner Service Account
resource "azurerm_federated_identity_credential" "runner_federated_credential" {
  count               = local.create_runner_identity ? 1 : 0
  name                = lookup(var.resource_names, "runner_federated_credential", join("-", [var.name, "runner-federated-credential", var.random_string_salt]))
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.runner_workload_identity[0].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks_cluster.oidc_issuer_url
  subject             = "system:serviceaccount:${var.namespace}:${var.runner_service_account_name}"
}

# Federated Identity Credential for Script-Runner Service Account
resource "azurerm_federated_identity_credential" "script_runner_federated_credential" {
  count               = local.create_runner_identity ? 1 : 0
  name                = lookup(var.resource_names, "script_runner_federated_credential", join("-", [var.name, "script-runner-federated-credential", var.random_string_salt]))
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.runner_workload_identity[0].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks_cluster.oidc_issuer_url
  subject             = "system:serviceaccount:${var.namespace}:${var.script_runner_service_account_name}"
}

# Data source to get the Service Principal object ID
data "azuread_service_principal" "runner_keyvault_sp" {
  count     = var.service_principal_enabled ? 1 : 0
  client_id = var.service_principal_client_id
}

# Assign Key Vault Secrets User Role to Service Principal
resource "azurerm_role_assignment" "runner_sp_key_vault_secrets_user" {
  count                = var.service_principal_enabled ? 1 : 0
  principal_id         = data.azuread_service_principal.runner_keyvault_sp[0].object_id
  role_definition_name = "Key Vault Secrets User"
  scope                = azurerm_key_vault.keyvault.id
}

# Assign Reader role to Service Principal for Key Vault metadata
resource "azurerm_role_assignment" "runner_sp_key_vault_reader" {
  count                = var.service_principal_enabled ? 1 : 0
  principal_id         = data.azuread_service_principal.runner_keyvault_sp[0].object_id
  role_definition_name = "Reader"
  scope                = azurerm_key_vault.keyvault.id
}

# Assign Storage Blob Data Contributor Role to Service Principal
resource "azurerm_role_assignment" "runner_sp_blob_storage_role" {
  count                = var.service_principal_enabled ? 1 : 0
  principal_id         = data.azuread_service_principal.runner_keyvault_sp[0].object_id
  role_definition_name = "Storage Blob Data Contributor"
  scope                = azurerm_storage_account.stagging.id
}

