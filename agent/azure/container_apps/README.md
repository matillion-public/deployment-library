# Azure Container Apps Deployment for Matillion Agent

This directory contains Terraform configurations for deploying the Matillion DPC Agent using Azure Container Apps - a fully managed serverless container service.

## Overview

Azure Container Apps deployment provides:
- **Serverless Containers**: Fully managed container hosting
- **Fixed Replica Count**: Consistent container count (no auto-scaling - that is a K8s/AKS feature)
- **Integrated Security**: Managed Identity, Key Vault, and network isolation
- **Cost Effective**: Pay-per-use pricing model
- **Full Prerequisite Creation**: VNet, subnets, identity, Key Vault, and storage are all created automatically

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Azure Resource Group                    │
│                                                         │
│  ┌─────────────────────────────────────────────────────┐│
│  │  Virtual Network (10.0.0.0/16)                      ││
│  │  ┌────────────────────────┐ ┌─────────────────────┐ ││
│  │  │ Subnet 0 (10.0.0.0/23)│ │Subnet 1 (10.0.2.0/24│ ││
│  │  │ Delegated to           │ │ Service endpoints    │ ││
│  │  │ Microsoft.App/         │ │ (Storage, KeyVault)  │ ││
│  │  │ environments           │ │                      │ ││
│  │  └──────────┬─────────────┘ └─────────────────────┘ ││
│  └─────────────┼───────────────────────────────────────┘│
│                │                                         │
│  ┌─────────────▼───────────────────────────────────────┐│
│  │    Container Apps Environment                        ││
│  │  ┌───────────────────────────────────────┐          ││
│  │  │  Container App (Matillion Agent)      │          ││
│  │  │  - UserAssigned Managed Identity      │          ││
│  │  │  - Workload Profile: agentpool (D4)   │          ││
│  │  │  - Replicas: 2 (fixed)               │          ││
│  │  └───────────────────────────────────────┘          ││
│  └─────────────────────────────────────────────────────┘│
│                                                         │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────────┐│
│  │  Key Vault   │ │   Storage    │ │  Log Analytics   ││
│  │  (Secrets)   │ │  Account     │ │  Workspace       ││
│  └──────────────┘ └──────────────┘ └──────────────────┘│
└─────────────────────────────────────────────────────────┘
```

## Module Structure

This deployment follows the same modular pattern as the AKS deployment:

```
agent/azure/container_apps/     # Root configuration
├── main.tf                     # Calls networking + container-apps modules
├── variables.tf                # Input variables
├── outputs.tf                  # Output values
├── provider.tf                 # Azure provider config
├── backend.tf                  # State backend config
└── terraform.example.tfvars    # Example variable values

modules/azure/networking/       # Shared networking module
├── main.tf                     # VNet, subnets, NSG, NAT Gateway
├── variables.tf
└── outputs.tf

modules/azure/container-apps/   # Container Apps module
├── main.tf                     # CA env, app, KV, storage, identity, roles
├── variables.tf
└── outputs.tf
```

## Prerequisites

- [Terraform 1.0+](https://www.terraform.io/downloads.html)
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- Azure subscription with Container Apps enabled
- A pre-existing resource group

### Required Azure Permissions

```bash
# Login to Azure
az login

# Set subscription
az account set --subscription "your-subscription-id"

# Register required providers
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights
```

## Networking Requirements

### Container Apps Subnet Restrictions

Azure Container Apps has specific subnet requirements that differ from AKS. This deployment handles them automatically via `cidrsubnet()`, but they are important to understand:

| Requirement | Detail |
|---|---|
| **Minimum subnet size** | `/23` (512 addresses). Azure reserves addresses for internal Container Apps infrastructure. A `/24` or smaller **will fail deployment**. |
| **Recommended subnet size** | `/23` for most workloads. Use `/21` if you expect many Container App environments or revisions. |
| **Subnet delegation** | The subnet **must** be delegated to `Microsoft.App/environments`. No other resources can share this delegated subnet. |
| **Dedicated subnet** | The Container Apps Environment subnet cannot be shared with other services (e.g. VMs, AKS, Application Gateway). |
| **Service endpoints** | `Microsoft.Storage` and `Microsoft.KeyVault` are configured for Key Vault and storage access. |
| **NSG** | An NSG allowing HTTPS (443) inbound is attached to all subnets. |

> **Why /23 and not /24?** Azure Container Apps uses the infrastructure subnet to provision internal load balancers, envoy proxies, and platform components. A `/24` (256 addresses) does not provide enough addresses and Azure will reject the deployment with an error.

### How Subnets Are Calculated

Subnets are dynamically calculated using Terraform's `cidrsubnet()` function to avoid CIDR clashes (same pattern as the AWS deployments):

```hcl
# From main.tf — subnet_configs passed to the networking module
subnet_configs = [
  {
    newbits = 7    # cidrsubnet("10.0.0.0/16", 7, 0) = 10.0.0.0/23  (CA environment)
    netnum  = 0
    delegation = { ... Microsoft.App/environments ... }
  },
  {
    newbits = 8    # cidrsubnet("10.0.0.0/16", 8, 2) = 10.0.2.0/24  (services)
    netnum  = 2
    delegation = null
  }
]
```

The VNet address space defaults to `10.0.0.0/16`. To customize, override `vnet_address_space` in the networking module call and adjust `newbits`/`netnum` accordingly. **Subnet 0 must remain /23 or larger** and **must retain the `Microsoft.App/environments` delegation**.

## Quick Start

### 1. Configure Variables

Create `terraform.tfvars` from the example:

```hcl
# Azure Configuration
azure_subscription_id = "12345678-1234-1234-1234-123456789abc"
azure_tenant_id       = "12345678-1234-1234-1234-123456789abc"
resource_group_name   = "matillion-agent-rg"
location              = "eastus"

# Resource Naming
name = "matillion-agent"

# Matillion Configuration
matillion_cloud_region = "eu1"
account_id             = "your-matillion-account-id"
agent_id               = "your-unique-agent-id"
client_id              = "your-oauth-client-id"
client_secret          = "your-oauth-client-secret"

# Optional
container_image_url = "matillion.azurecr.io/cloud-agent:current"
tags = {
  Environment = "production"
  Project     = "matillion-agent"
}
```

### 2. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

### 3. Verify Deployment

```bash
# Check Container App status
az containerapp show \
  --name <container_app_name from output> \
  --resource-group matillion-agent-rg

# View logs
az containerapp logs show \
  --name <container_app_name from output> \
  --resource-group matillion-agent-rg
```

## Configuration Options

### Container Configuration

| Variable | Default | Description |
|---|---|---|
| `container_cpu` | `"1.0"` | CPU allocation per container |
| `container_memory` | `"4Gi"` | Memory allocation per container |
| `replica_count` | `2` | Fixed number of running replicas (no auto-scaling) |
| `container_image_url` | `matillion.azurecr.io/cloud-agent:current` | Agent container image |

### Workload Profiles

| Variable | Default | Description |
|---|---|---|
| `workload_profile_type` | `"D4"` | VM type (D4=4vCPU/16GB, D8=8vCPU/32GB, D16=16vCPU/64GB) |
| `workload_profile_max_count` | `1` | Max instances in the workload profile |
| `zone_redundancy_enabled` | `true` | Zone redundancy for the environment |

### Networking

| Variable | Default | Description |
|---|---|---|
| `enable_nat_gateway` | `false` | Enable NAT Gateway for controlled outbound egress |
| `nat_gateway_idle_timeout` | `10` | NAT Gateway idle timeout in minutes (4-120) |

### Environment-Specific Examples

**Development:**
```hcl
replica_count              = 1
workload_profile_type      = "D4"
zone_redundancy_enabled    = false
```

**Production:**
```hcl
replica_count              = 2
workload_profile_type      = "D8"
zone_redundancy_enabled    = true
enable_nat_gateway         = true
```

## Security

### Resources Created Automatically

- **User Assigned Managed Identity** with roles:
  - `AcrPull` (subscription scope) - pull container images
  - `Storage Account Contributor` - manage storage
  - `Storage Blob Data Contributor` - read/write blobs
  - `Key Vault Secrets Officer` - manage secrets
  - `Key Vault Secrets User` - read secrets
  - `Reader` on Key Vault - metadata access
- **Key Vault** - RBAC-enabled, network-restricted to VNet subnets, 7-day soft delete
- **Storage Account** - Standard LRS, no public access
- **Key Vault Administrator** role assigned to the deployer for management

### Network Security

- Key Vault network ACLs restrict access to VNet subnets only (default deny, Azure Services bypass)
- NSG on all subnets allows only HTTPS (443) inbound

## Monitoring

### Log Analytics Queries

```kusto
// Container logs
ContainerAppConsoleLogs_CL
| where ContainerAppName_s contains "matillion"
| order by TimeGenerated desc

// Resource usage warnings
ContainerAppSystemLogs_CL
| where EventType_s == "Warning"
```

## Limitations

- **No Auto-scaling**: Container Apps in this deployment uses a fixed replica count. Auto-scaling is a Kubernetes/AKS feature.
- **Single Container**: No sidecar support (unlike AKS). Metrics sidecar not available.
- **Subnet Restrictions**: Infrastructure subnet must be /23 or larger, delegated to `Microsoft.App/environments`, and dedicated (not shared).

For auto-scaling, sidecar support, and advanced networking, consider the [AKS deployment](../aks/) instead.

## Cleanup

```bash
terraform destroy
```

## Comparison with AKS Deployment

| Feature | Container Apps | AKS |
|---|---|---|
| **Management** | Fully Managed | Managed Control Plane |
| **Scaling** | Fixed replica count | Auto-scaling (HPA) |
| **Networking** | Dedicated /23 subnet required | /24 subnets sufficient |
| **Sidecar Support** | No | Yes |
| **Cost** | Pay-per-use | Node-based |
| **Complexity** | Low | High |
| **Prerequisites** | Created automatically | Created automatically |
