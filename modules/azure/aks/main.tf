# Data source to get the current Azure client configuration
data "azurerm_client_config" "current" {}

data "http" "terraform_runner_external_ip" {
  url = "https://ipv4.icanhazip.com"
}

# User Assigned Managed Identity
resource "azurerm_user_assigned_identity" "aks_identity" {
  name                = join("-", [var.name, "aks-identity", var.random_string_salt])
  location            = var.location
  resource_group_name = var.resource_group_name
}

# Azure Kubernetes Service (AKS) Cluster
resource "azurerm_kubernetes_cluster" "aks_cluster" {
  name                = join("-", [var.name, "aks-cluster", var.random_string_salt])
  location            = var.location
  resource_group_name = var.resource_group_name
  
  dynamic "api_server_access_profile" {
    for_each = var.is_private_cluster ? [] : [1]
    content {
      authorized_ip_ranges = concat(var.authorized_ip_ranges, [join("", [trimspace(data.http.terraform_runner_external_ip.response_body), "/32"])])
    }
  }

  default_node_pool {
    name                 = "agentpool2"
    vm_size              = var.vm_size
    os_disk_size_gb      = var.node_disk_size
    auto_scaling_enabled = true
    min_count            = 2
    max_count            = var.desired_node_count + 2
    node_count           = var.desired_node_count  
    vnet_subnet_id       = var.subnet_ids[0]
  }

  identity {
    type = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks_identity.id]
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    service_cidr      = "10.2.0.0/16"
    dns_service_ip    = "10.2.0.10"
  }
  
  private_cluster_enabled = var.is_private_cluster

  dns_prefix = join("-", [var.name, "aks", var.random_string_salt])

  oidc_issuer_enabled       = var.workload_identity_enabled
  workload_identity_enabled = var.workload_identity_enabled

  tags = var.tags
}

# Log Analytics for AKS Logs
resource "azurerm_log_analytics_workspace" "aks_log_workspace" {
  name                = join("-", [var.name, "log-workspace", var.random_string_salt])
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
}

# Blob Storage Account
resource "azurerm_storage_account" "stagging" {
  name                     = substr(lower(join("", ["stagging", var.random_string_salt])), 0, 24)
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  allow_nested_items_to_be_public = false
}

# Key Vault
resource "azurerm_key_vault" "keyvault" {
  name                = join("-", [var.name, var.random_string_salt])
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  soft_delete_retention_days = 7
  enable_rbac_authorization = true
}

# Assign Key Vault Administrator role to current client for management
resource "azurerm_role_assignment" "current_client_key_vault_admin" {
  scope                = azurerm_key_vault.keyvault.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Assign Storage Blob Data Contributor Role to Managed Identity
resource "azurerm_role_assignment" "blob_storage_role" {
  principal_id   = azurerm_user_assigned_identity.aks_identity.principal_id
  role_definition_name = "Storage Account Contributor"
  scope          = azurerm_storage_account.stagging.id
}

# Assign Key Vault Secrets User Role to Managed Identity
resource "azurerm_role_assignment" "key_vault_officer_role" {
  principal_id   = azurerm_user_assigned_identity.aks_identity.principal_id
  role_definition_name = "Key Vault Secrets Officer"
  scope          = azurerm_key_vault.keyvault.id
}

# Assign Key Vault Secrets User Role to Managed Identity
resource "azurerm_role_assignment" "key_vault_role" {
  principal_id   = azurerm_user_assigned_identity.aks_identity.principal_id
  role_definition_name = "Key Vault Secrets User"
  scope          = azurerm_key_vault.keyvault.id
}

# User Assigned Managed Identity for Agent Workload
resource "azurerm_user_assigned_identity" "agent_workload_identity" {
  count               = var.workload_identity_enabled ? 1 : 0
  name                = join("-", [var.name, "agent-workload-identity", var.random_string_salt])
  location            = var.location
  resource_group_name = var.resource_group_name
}

# Assign Storage Blob Data Contributor Role to Agent Workload Identity
resource "azurerm_role_assignment" "agent_blob_storage_role" {
  count              = var.workload_identity_enabled ? 1 : 0
  principal_id       = azurerm_user_assigned_identity.agent_workload_identity[0].principal_id
  role_definition_name = "Storage Blob Data Contributor"
  scope              = azurerm_storage_account.stagging.id
}

# Assign Key Vault Secrets User Role to Agent Workload Identity
resource "azurerm_role_assignment" "agent_key_vault_role" {
  count              = var.workload_identity_enabled ? 1 : 0
  principal_id       = azurerm_user_assigned_identity.agent_workload_identity[0].principal_id
  role_definition_name = "Key Vault Secrets User"
  scope              = azurerm_key_vault.keyvault.id
}

# Assign Reader Role to Agent Workload Identity for Key Vault metadata
resource "azurerm_role_assignment" "agent_key_vault_reader_role" {
  count              = var.workload_identity_enabled ? 1 : 0
  principal_id       = azurerm_user_assigned_identity.agent_workload_identity[0].principal_id
  role_definition_name = "Reader"
  scope              = azurerm_key_vault.keyvault.id
}

# Assign Reader Role to Agent Workload Identity at Subscription level
# This allows az login --identity to list subscriptions and authenticate properly
resource "azurerm_role_assignment" "agent_subscription_reader_role" {
  count              = var.workload_identity_enabled ? 1 : 0
  principal_id       = azurerm_user_assigned_identity.agent_workload_identity[0].principal_id
  role_definition_name = "Reader"
  scope              = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
}

# Federated Identity Credential for Agent Service Account
resource "azurerm_federated_identity_credential" "agent_federated_credential" {
  count               = var.workload_identity_enabled ? 1 : 0
  name                = join("-", [var.name, "agent-federated-credential", var.random_string_salt])
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.agent_workload_identity[0].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks_cluster.oidc_issuer_url
  subject             = "system:serviceaccount:${var.name}:${var.name}-sa"
}

# Data source to get the Service Principal object ID
data "azuread_service_principal" "agent_keyvault_sp" {
  count     = var.service_principal_enabled ? 1 : 0
  client_id = var.service_principal_client_id
}

# Assign Key Vault Secrets User Role to Service Principal
resource "azurerm_role_assignment" "agent_sp_key_vault_secrets_user" {
  count                = var.service_principal_enabled ? 1 : 0
  principal_id         = data.azuread_service_principal.agent_keyvault_sp[0].object_id
  role_definition_name = "Key Vault Secrets User"
  scope                = azurerm_key_vault.keyvault.id
}

# Assign Reader role to Service Principal for Key Vault metadata
resource "azurerm_role_assignment" "agent_sp_key_vault_reader" {
  count                = var.service_principal_enabled ? 1 : 0
  principal_id         = data.azuread_service_principal.agent_keyvault_sp[0].object_id
  role_definition_name = "Reader"
  scope                = azurerm_key_vault.keyvault.id
}

# Assign Storage Blob Data Contributor Role to Service Principal
resource "azurerm_role_assignment" "agent_sp_blob_storage_role" {
  count                = var.service_principal_enabled ? 1 : 0
  principal_id         = data.azuread_service_principal.agent_keyvault_sp[0].object_id
  role_definition_name = "Storage Blob Data Contributor"
  scope                = azurerm_storage_account.stagging.id
}

