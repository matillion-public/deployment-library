# Azure Kubernetes Service (AKS) Deployment with Terraform

This repository contains Terraform configurations for deploying an Azure Kubernetes Service (AKS) cluster along with associated resources such as a User Assigned Managed Identity, Log Analytics Workspace, Storage Account, and Key Vault.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Configuration Files](#configuration-files)
  - [main.tf](#maintf)
  - [variables.tf](#variablestf)
  - [outputs.tf](#outputstf)
- [Usage](#usage)
- [Outputs](#outputs)

## Prerequisites

- Azure CLI installed and authenticated
- Terraform installed
- An Azure subscription
- Service Principal for Key Vault access (see [Service Principal Setup](#service-principal-setup))

## Configuration Files

### main.tf

Defines the main resources for the deployment including:
- Azure Kubernetes Service (AKS) Cluster
- User Assigned Managed Identity
- Log Analytics Workspace
- Storage Account
- Key Vault
- Role Assignments

### variables.tf

Defines the input variables used in the Terraform configurations:
- `name`: Name prefix for resources
- `location`: Azure region for resources
- `resource_group_name`: Resource group name
- `subnet_id`: Subnet ID for AKS
- `appgw_subnet_id`: Subnet ID for Application Gateway
- `tags`: Tags to apply to resources
- `desired_node_count`: Desired number of nodes in the AKS cluster
- `random_string_salt`: Random string for uniqueness
- `is_private_cluster`: Boolean to enable private cluster
- `authorized_ip_ranges`: List of authorized IP ranges for API server
- `app_gw_id`: Application Gateway ID
- `service_principal_client_id`: Service Principal Client ID for Key Vault access
- `service_principal_secret`: Service Principal Secret for Key Vault access

### outputs.tf

Defines the outputs of the Terraform configurations:
- `kubeconfig`: Path to the Kubernetes configuration file
- `cluster_name`: Name of the AKS cluster
- `aks_identity_principal_id`: Principal ID of the User Assigned Managed Identity

## Service Principal Setup

To create the required Service Principal for Key Vault access, follow these steps:

### 1. Create the Service Principal

```bash
# Create a Service Principal
az ad sp create-for-rbac --name "matillion-agent-keyvault-sp" --role "Key Vault Secrets User" --scopes "/subscriptions/{subscription-id}/resourceGroups/{resource-group-name}/providers/Microsoft.KeyVault/vaults/{key-vault-name}"
```

This command will output:
```json
{
  "appId": "<your-service-principal-app-id>",
  "displayName": "matillion-agent-keyvault-sp",
  "password": "<your-service-principal-password>",
  "tenant": "<your-tenant-id>"
}
```

### 2. Update terraform.tfvars

Add the Service Principal credentials to your `terraform.tfvars` file (ensure this file is in `.gitignore`):

```hcl
# Service Principal for Key Vault Access
service_principal_client_id = "<your-service-principal-app-id>"
service_principal_secret    = "<your-service-principal-password>"
```

### 3. Additional Permissions (if needed)

If you encounter permission issues, you may need to grant additional roles:

```bash
# Grant Key Vault Secrets Officer role (if needed for secret management)
az role assignment create \
  --assignee "<your-service-principal-app-id>" \
  --role "Key Vault Secrets Officer" \
  --scope "/subscriptions/{subscription-id}/resourceGroups/{resource-group-name}/providers/Microsoft.KeyVault/vaults/{key-vault-name}"

# Grant Reader role for Key Vault metadata access
az role assignment create \
  --assignee "<your-service-principal-app-id>" \
  --role "Reader" \
  --scope "/subscriptions/{subscription-id}/resourceGroups/{resource-group-name}/providers/Microsoft.KeyVault/vaults/{key-vault-name}"
```

**⚠️ CRITICAL SECURITY WARNING:**
- **NEVER commit real Service Principal credentials to version control**
- Replace all placeholder values (`<your-*>`) with actual credentials only in your local `terraform.tfvars` file
- Add `terraform.tfvars` to your `.gitignore` file to prevent accidental commits
- Store the Service Principal secret securely using Azure Key Vault or environment variables
- Rotate credentials regularly
- Apply principle of least privilege
- Use Azure Workload Identity or Managed Identity when possible instead of Service Principal credentials

## Outputs
After applying the Terraform configurations, the following outputs will be available:

- kubeconfig: Path to the Kubernetes configuration file for use with kubectl
- cluster_name: Name of the deployed AKS cluster
- aks_identity_principal_id: Principal ID of the User Assigned Managed Identity