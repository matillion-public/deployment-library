# Azure Container Apps Deployment for Matillion Agent

This directory contains Terraform configurations for deploying the Matillion DPC Agent using Azure Container Apps - a fully managed serverless container service.

## 🎯 Overview

Azure Container Apps deployment provides:
- **Serverless Containers**: Fully managed container hosting
- **Auto-scaling**: Built-in scaling based on HTTP traffic and custom metrics
- **Microservices Ready**: Service discovery and distributed application patterns
- **Integrated Security**: Managed Identity and Key Vault integration
- **Cost Effective**: Pay-per-use pricing model

## 🏗️ Architecture

```
┌─────────────────────────────────────┐
│         Azure Resource Group        │
│  ┌─────────────────────────────────┐ │
│  │    Container Apps Environment   │ │
│  │  ┌─────────────────────────────┐ │ │
│  │  │      Container App          │ │ │
│  │  │  ┌─────────────────────────┐ │ │ │
│  │  │  │   Matillion Agent       │ │ │ │
│  │  │  │     (Single Container)  │ │ │ │
│  │  │  └─────────────────────────┘ │ │ │
│  │  └─────────────────────────────┘ │ │
│  └─────────────────────────────────┘ │
│  ┌─────────────────────────────────┐ │
│  │         Key Vault               │ │
│  │    (OAuth Credentials)          │ │
│  └─────────────────────────────────┘ │
│  ┌─────────────────────────────────┐ │
│  │    Log Analytics Workspace     │ │
│  │       (Monitoring & Logs)       │ │
│  └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

## 📋 Prerequisites

- [Terraform 1.0+](https://www.terraform.io/downloads.html)
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- Azure subscription with Container Apps enabled
- Virtual network with dedicated subnet for Container Apps

### Required Azure Permissions

```bash
# Login to Azure
az login

# Set subscription
az account set --subscription "your-subscription-id"

# Register Container Apps provider
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.OperationalInsights
```

## 🚀 Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd agent-deployment/agent/azure/container_apps
```

### 2. Configure Variables

Create `terraform.tfvars` from the example:

```hcl
# Azure Configuration
subscription_id      = "12345678-1234-1234-1234-123456789012"
resource_group_name  = "matillion-agent-rg"
location            = "East US"
resource_name       = "matillion-agent"

# Networking
subnet_id = "/subscriptions/.../resourceGroups/.../providers/Microsoft.Network/virtualNetworks/.../subnets/container-apps-subnet"

# Matillion Configuration
account_id               = "your-matillion-account-id"
agent_id                = "your-unique-agent-id"
matillion_cloud_region  = "us-east-1"
client_id              = "your-oauth-client-id"
client_secret          = "your-oauth-client-secret"

# Container Configuration
container_image_url = "matillion.azurecr.io/cloud-agent:current"

# Resource Names
key_vault_name                 = "matillion-agent-kv"
managed_identity_name          = "matillion-agent-identity"
log_analytics_workspace_name   = "matillion-agent-logs"

# Resource Creation Options
create_key_vault        = true
create_managed_identity = true

# Optional: Tags
tags = {
  Environment = "production"
  Project     = "matillion-agent"
  Owner       = "data-team"
}
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review deployment plan
terraform plan

# Deploy infrastructure
terraform apply
```

### 4. Verify Deployment

```bash
# Check Container App status
az containerapp show --name matillion-agent-app --resource-group matillion-agent-rg

# View logs
az containerapp logs show --name matillion-agent-app --resource-group matillion-agent-rg
```

## ⚙️ Configuration Options

### Resource Creation Options

#### Create All Resources (Default)
```hcl
create_key_vault        = true
create_managed_identity = true
```

#### Use Existing Resources
```hcl
create_key_vault        = false
create_managed_identity = false
# Ensure existing resources are specified in variables
```

### Container Configuration

#### Standard Configuration
```hcl
# Default container specs
template {
  min_replicas = 2
  max_replicas = 2
  container {
    cpu    = "1.0"
    memory = "4Gi"
  }
}
```

#### High-Performance Configuration
```hcl
# Edit main.tf for custom specs
template {
  min_replicas = 3
  max_replicas = 10
  container {
    cpu    = "2.0"
    memory = "8Gi"
  }
}
```

### Workload Profiles

Container Apps supports different workload profiles:

| Profile Type | vCPU | Memory | Use Case |
|-------------|------|--------|----------|
| `D4` | 4 | 16GB | Standard workload |
| `D8` | 8 | 32GB | High-performance |
| `D16` | 16 | 64GB | Memory-intensive |

## 📊 Monitoring and Logging

### Built-in Monitoring

Container Apps includes comprehensive monitoring:

- **Application Insights**: Automatic telemetry collection
- **Log Analytics**: Centralized log aggregation
- **Metrics**: CPU, Memory, Request count, Response time
- **Health Probes**: Liveness and readiness checks

### Log Analytics Queries

```kusto
// Container logs
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "matillion-agent-app"
| order by TimeGenerated desc

// Resource usage
ContainerAppSystemLogs_CL
| where ContainerAppName_s == "matillion-agent-app"
| where EventType_s == "Warning"
```

### Application Insights Integration

```bash
# Enable Application Insights (optional)
az monitor app-insights component create \
  --app matillion-agent-insights \
  --location "East US" \
  --resource-group matillion-agent-rg
```

## 🔒 Security Configuration

### Managed Identity

The deployment creates a User Assigned Managed Identity with:

- **AcrPull**: Access to Azure Container Registry
- **Storage Account Contributor**: Access to storage accounts
- **Storage Blob Data Contributor**: Read/write blob storage
- **Storage Blob Data Reader**: Read blob storage
- **Key Vault Secrets Officer**: Manage Key Vault secrets

### Key Vault Integration

```hcl
# Automatic secret management
secret {
  name  = "matillion-client-id"
  value = var.client_id
}

secret {
  name  = "matillion-client-secret"
  value = var.client_secret
}
```

### Network Security

```hcl
# Key Vault network restrictions
network_acls {
  default_action             = "Deny"
  bypass                     = "AzureServices"
  virtual_network_subnet_ids = [var.subnet_id]
}
```

## 🔧 Operations

### Scaling Operations

#### Manual Scaling
```bash
# Update container app with new replica count
az containerapp update --name matillion-agent-app \
  --resource-group matillion-agent-rg \
  --min-replicas 1 --max-replicas 5
```

#### Auto-scaling Rules
```bash
# Add HTTP scaling rule
az containerapp revision copy --name matillion-agent-app \
  --resource-group matillion-agent-rg \
  --scale-rule-name http-requests \
  --scale-rule-type http \
  --scale-rule-http-concurrent-requests 100
```

### Updates and Maintenance

#### Application Updates
```bash
# Update container image
az containerapp update --name matillion-agent-app \
  --resource-group matillion-agent-rg \
  --image "matillion.azurecr.io/cloud-agent:v2.0.0"
```

#### Configuration Updates
```bash
# Update environment variables
az containerapp update --name matillion-agent-app \
  --resource-group matillion-agent-rg \
  --set-env-vars "NEW_ENV_VAR=value"
```

### Troubleshooting

#### Container Issues
```bash
# Check container app status
az containerapp show --name matillion-agent-app \
  --resource-group matillion-agent-rg \
  --query "properties.provisioningState"

# View recent logs
az containerapp logs show --name matillion-agent-app \
  --resource-group matillion-agent-rg \
  --tail 100

# Check revisions
az containerapp revision list --name matillion-agent-app \
  --resource-group matillion-agent-rg
```

#### Authentication Issues
```bash
# Check managed identity
az identity show --name matillion-agent-identity \
  --resource-group matillion-agent-rg

# Verify Key Vault access
az keyvault secret list --vault-name matillion-agent-kv
```

#### Network Issues
```bash
# Check subnet configuration
az network vnet subnet show --ids "/subscriptions/.../subnets/container-apps-subnet"

# Test connectivity
az containerapp exec --name matillion-agent-app \
  --resource-group matillion-agent-rg \
  --command "/bin/sh"
```

## 💰 Cost Optimization

### Pricing Model

Container Apps charges for:
- **vCPU seconds**: Actual CPU consumption
- **Memory GB-seconds**: Actual memory usage
- **HTTP requests**: Ingress traffic (if enabled)

### Optimization Strategies

#### Right-sizing Resources
```bash
# Monitor resource usage
az monitor metrics list --resource /subscriptions/.../containerApps/matillion-agent-app \
  --metric "CpuPercentage,MemoryPercentage"
```

#### Efficient Scaling
```hcl
# Optimize min/max replicas
template {
  min_replicas = 1  # Reduce idle costs
  max_replicas = 5  # Limit maximum costs
}
```

#### Reserved Capacity
Consider Azure Reserved Instances for predictable workloads.

## 🚨 Limitations

### Container Apps Constraints

- **Single Container**: No sidecar support (unlike AKS)
- **Limited Networking**: No custom networking features
- **Scaling Limits**: Maximum 300 replicas per app
- **Storage**: Temporary storage only

### Metrics Considerations

⚠️ **Important**: This deployment **does not include** the metrics sidecar container available in the Kubernetes deployments (AKS/EKS). Container Apps supports only single-container deployments.

For comprehensive metrics collection, consider:
- Using the AKS deployment instead
- Implementing metrics collection within the agent container
- Using Azure Application Insights for monitoring

## 🔄 Migration Paths

### From Container Apps to AKS

If you need advanced features like metrics sidecars:

```bash
# Deploy AKS version
cd ../aks
terraform init
terraform apply
```

### From ECS to Container Apps

Migration considerations:
- Single container limitation
- Different environment variable handling
- Azure-specific managed identity vs IAM roles

## 🧹 Cleanup

### Destroy Infrastructure

```bash
# Destroy all resources
terraform destroy

# Verify cleanup
az group show --name matillion-agent-rg
```

### Manual Cleanup (if needed)

```bash
# Delete resource group (removes all resources)
az group delete --name matillion-agent-rg --yes --no-wait

# Clean up Terraform state
rm -rf .terraform*
rm terraform.tfstate*
```

## 📈 Performance Considerations

### Resource Allocation

```hcl
# Optimized for different workloads
container {
  # Light workload
  cpu = "0.5"
  memory = "1Gi"
  
  # Standard workload (recommended)
  cpu = "1.0"
  memory = "4Gi"
  
  # Heavy workload
  cpu = "2.0"
  memory = "8Gi"
}
```

### Environment-Specific Configurations

#### Development
```hcl
template {
  min_replicas = 0  # Scale to zero
  max_replicas = 2
}
```

#### Production
```hcl
template {
  min_replicas = 2  # Always available
  max_replicas = 10
}
```

## 🤝 Support

For Container Apps specific issues:

1. **Azure Status**: [Azure Status Page](https://status.azure.com/)
2. **Container Apps Docs**: [Azure Container Apps Documentation](https://docs.microsoft.com/en-us/azure/container-apps/)
3. **Azure Support**: Create support case for platform issues
4. **GitHub Issues**: Report deployment configuration problems

## 📚 Additional Resources

- [Azure Container Apps Documentation](https://docs.microsoft.com/en-us/azure/container-apps/)
- [Container Apps Pricing](https://azure.microsoft.com/en-us/pricing/details/container-apps/)
- [Terraform AzureRM Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure Container Apps Best Practices](https://docs.microsoft.com/en-us/azure/container-apps/compare-options)

## ⚖️ Comparison with Other Deployment Methods

| Feature | Container Apps | AKS | ECS |
|---------|----------------|-----|-----|
| **Management** | Fully Managed | Managed Control Plane | Fully Managed |
| **Scaling** | Auto (0-300) | Manual/HPA | Manual/Auto |
| **Networking** | Basic | Advanced | Basic |
| **Sidecar Support** | ❌ | ✅ | ❌ |
| **Cost** | Pay-per-use | Node-based | Task-based |
| **Complexity** | Low | High | Medium |

Choose Container Apps for:
- Simple containerized applications
- Cost-effective serverless deployment
- Minimal operational overhead
- Auto-scaling requirements

Choose AKS for:
- Complex microservices architectures
- Advanced networking needs
- Sidecar container requirements (metrics)
- Full Kubernetes ecosystem access