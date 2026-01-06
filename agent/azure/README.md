# Azure AKS Deployment for Matillion Agent

This directory contains Terraform configurations for deploying the Matillion DPC Agent on Azure Kubernetes Service (AKS) with comprehensive monitoring capabilities.

## Overview

The Azure deployment provides:
- **AKS Cluster**: Fully managed Kubernetes service
- **Agent Pods**: Main Matillion Agent with metrics sidecar
- **Monitoring**: Built-in Prometheus metrics collection
- **Security**: Managed Identity and Key Vault integration
- **Scalability**: Configurable VM sizes and replica counts

## Architecture

```
┌────────────────────────────────────────┐
│           Azure Resource Group         │
│  ┌──────────────────────────────────┐  │
│  │          AKS Cluster             │  │
│  │  ┌─────────────────────────────┐ │  │
│  │  │         Agent Pod           │ │  │
│  │  │  ┌──────────┐ ┌───────────┐ │ │  │
│  │  │  │Container │ │ Sidecar   │ │ │  │
│  │  │  └──────────┘ └───────────┘ │ │  │
│  │  └─────────────────────────────┘ │  │
│  └──────────────────────────────────┘  │
│  ┌─────────────────────────────────┐   │
│  │        Key Vault                │   │
│  │    (OAuth Credentials)          │   │
│  └─────────────────────────────────┘   │
│  ┌─────────────────────────────────┐   │
│  │     Storage Account             │   │
│  │    (Staging Data)               │   │
│  └─────────────────────────────────┘   │
└────────────────────────────────────────┘
```

## Prerequisites

- [Terraform 1.0+](https://www.terraform.io/downloads.html)
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- Azure subscription with appropriate permissions
- Contributor access to resource group

### Required Azure Permissions

```bash
# Login to Azure
az login

# Set subscription
az account set --subscription "your-subscription-id"

# Verify permissions
az role assignment list --assignee $(az account show --query user.name -o tsv)
```

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd agent-deployment/agent/azure/aks
```

### 2. Configure Variables

Create `terraform.tfvars`:

```hcl
# Azure Configuration
azure_subscription_id = "12345678-1234-1234-1234-123456789012"
resource_group_name   = "matillion-agent-rg"
location             = "East US"
name                 = "matillion-agent"

# Matillion Configuration  
agent_id            = "your-unique-agent-id"
account_id          = "your-matillion-account-id"
matillion_region    = "us-east-1"
client_id          = "your-oauth-client-id"
client_secret      = "your-oauth-client-secret"

# AKS Cluster Configuration
vm_size            = "Standard_D4s_v4"    # 4 vCPU, 16GB RAM
node_disk_size     = 250                   # GB
desired_node_count = 3                     # Initial node count
is_private_cluster = false                 # Public for testing
authorized_ip_ranges = ["0.0.0.0/0"]     # Restrict in production

# Agent Configuration
agent_replicas = 2                         # Number of agent pods
metrics_exporter_image_repository = "brbajematillion/metrics-sidecar"
metrics_exporter_image_tag = "latest"

# Optional: Customize tags
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
# Get AKS credentials
az aks get-credentials --resource-group matillion-agent-rg --name <cluster-name>

# Check agent pods
kubectl get pods -n matillion-agent

# Check metrics endpoint
kubectl port-forward -n matillion-agent deployment/matillion-agent-dpc-agent 8000:8000
curl http://localhost:8000/metrics
```

## Configuration Options

### VM Size Options

| VM Size | vCPU | RAM | Use Case |
|---------|------|-----|----------|
| `Standard_D2s_v4` | 2 | 8GB | Development |
| `Standard_D4s_v4` | 4 | 16GB | Testing |
| `Standard_D8s_v4` | 8 | 32GB | Production |
| `Standard_D16s_v4` | 16 | 64GB | High Load |

### Network Configuration

#### Public Cluster (Development)
```hcl
is_private_cluster = false
authorized_ip_ranges = ["your.public.ip.address/32"]
```

#### Private Cluster (Production)
```hcl
is_private_cluster = true
authorized_ip_ranges = ["10.0.0.0/8", "172.16.0.0/12"]
```

### Scaling Configuration

#### Small Environment
```hcl
desired_node_count = 2
agent_replicas = 1
vm_size = "Standard_D2s_v4"
```

#### Production Environment
```hcl
desired_node_count = 5
agent_replicas = 3
vm_size = "Standard_D8s_v4"
node_disk_size = 500
```

## Monitoring Integration

### Prometheus Metrics

The deployment automatically includes metrics collection:

```yaml
# Prometheus annotations (automatically applied)
prometheus.io/scrape: "true"
prometheus.io/port: "8000"
prometheus.io/path: "/metrics"
```

Available metrics:
- `app_version_info` - Build information
- `app_agent_status` - Running status (1=running, 0=stopped)
- `app_active_task_count` - Active tasks
- `app_active_request_count` - Active requests
- `app_open_sessions_count` - Open database sessions

### Azure Monitor Integration

```bash
# Enable Container Insights
az aks enable-addons --resource-group matillion-agent-rg \
  --name <cluster-name> --addons monitoring \
  --workspace-resource-id <log-analytics-workspace-id>
```

### Log Analytics Queries

```kusto
// Agent pod logs
ContainerLog
| where Name contains "agent"
| order by TimeGenerated desc

// Resource usage
Perf
| where ObjectName == "K8SContainer"
| where CounterName == "cpuUsageNanoCores"
| summarize avg(CounterValue) by Computer
```

## Security Configuration

### Managed Identity

The deployment creates a User Assigned Managed Identity with minimal permissions:

- **Storage Account Contributor**: Access to staging data
- **Key Vault Secrets User**: Read OAuth credentials
- **Key Vault Secrets Officer**: Manage secrets (deployment only)

### Key Vault Configuration

```hcl
# Automatic secret creation
resource "azurerm_key_vault_secret" "oauth_client_id" {
  name         = "oauth-client-id"
  value        = var.client_id
  key_vault_id = azurerm_key_vault.keyvault.id
}
```

### Network Security

```hcl
# Private cluster with authorized IP ranges
api_server_access_profile {
  authorized_ip_ranges = concat(
    var.authorized_ip_ranges,
    [format("%s/32", data.http.terraform_runner_external_ip.body)]
  )
}
```

## Operations

### Scaling Operations

#### Horizontal Scaling (Nodes)
```bash
# Scale node pool
az aks nodepool scale --resource-group matillion-agent-rg \
  --cluster-name <cluster-name> --name agentpool2 --node-count 5
```

#### Vertical Scaling (Agent Replicas)
```bash
# Update replica count
kubectl scale deployment/matillion-agent-dpc-agent \
  --namespace matillion-agent --replicas=4
```

### Updates and Maintenance

#### Terraform Updates
```bash
# Update configuration
vim terraform.tfvars

# Apply changes
terraform plan
terraform apply
```

#### AKS Cluster Updates
```bash
# Check available versions
az aks get-versions --location "East US"

# Upgrade cluster
az aks upgrade --resource-group matillion-agent-rg \
  --name <cluster-name> --kubernetes-version 1.27.0
```

### Troubleshooting

#### Pod Issues
```bash
# Check pod status
kubectl get pods -n matillion-agent

# View pod logs
kubectl logs -n matillion-agent deployment/matillion-agent-dpc-agent -c agent

# Check metrics sidecar
kubectl logs -n matillion-agent deployment/matillion-agent-dpc-agent -c metrics-exporter

# Describe pod for events
kubectl describe pod -n matillion-agent <pod-name>
```

#### Network Issues
```bash
# Check service endpoints
kubectl get endpoints -n matillion-agent

# Test internal DNS
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default
```

#### Authentication Issues
```bash
# Check managed identity
az identity show --ids $(terraform output managed_identity_id)

# Verify Key Vault access
az keyvault secret list --vault-name <vault-name>
```

## Cost Optimization

### Right-sizing

Monitor resource usage:
```bash
# CPU and memory usage
kubectl top nodes
kubectl top pods -n matillion-agent
```

### Spot Instances

```hcl
# Use spot instances for cost savings (development only)
default_node_pool {
  priority        = "Spot"
  eviction_policy = "Delete"
  spot_max_price  = 0.5  # USD per hour
}
```

### Reserved Capacity

Consider Azure Reserved VM Instances for predictable workloads.

## Cleanup

### Destroy Infrastructure

```bash
# Destroy all resources
terraform destroy

# Verify cleanup
az group show --name matillion-agent-rg
```

### Manual Cleanup (if needed)

```bash
# Force delete resource group
az group delete --name matillion-agent-rg --yes --no-wait

# Clean up Terraform state
rm -rf .terraform*
rm terraform.tfstate*
```

## Performance Tuning

### Node Configuration

```hcl
# High-performance configuration
vm_size = "Standard_D16s_v4"
node_disk_size = 1000
max_pods = 110  # Per node
```

### Agent Optimization

```hcl
# Optimized agent resources (in deployment module)
resources = {
  limits = {
    cpu    = "4"
    memory = "8Gi"
  }
  requests = {
    cpu    = "2"
    memory = "4Gi"
  }
}
```

## Support

For AKS-specific issues:

1. **Check Azure Status**: [Azure Status Page](https://status.azure.com/)
2. **Review AKS Logs**: Use Log Analytics workspace
3. **Azure Support**: Create support case for platform issues
4. **GitHub Issues**: Report deployment configuration problems

## Additional Resources

- [Azure AKS Documentation](https://docs.microsoft.com/en-us/azure/aks/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure Monitor Container Insights](https://docs.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-overview)
- [AKS Best Practices](https://docs.microsoft.com/en-us/azure/aks/best-practices)