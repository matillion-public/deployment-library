# Azure AKS Deployment for Matillion Runner

This directory contains Terraform configurations for deploying the Matillion Maia Runner on Azure Kubernetes Service (AKS) with comprehensive monitoring capabilities.

## Overview

The Azure deployment provides:
- **AKS Cluster**: Fully managed Kubernetes service
- **Runner Pods**: Main Matillion Runner with metrics sidecar
- **Monitoring**: Built-in Prometheus metrics collection
- **Security**: Managed Identity and Key Vault integration
- **Scalability**: Configurable VM sizes and replica counts

To put a runner into an AKS cluster you already run, beside any other runners, use [`aks-existing-cluster`](./aks-existing-cluster/) instead. Each runner gets its own namespace, managed identities and Key Vault, and the cluster is left alone.

## Architecture

```
┌────────────────────────────────────────┐
│           Azure Resource Group         │
│  ┌──────────────────────────────────┐  │
│  │          AKS Cluster             │  │
│  │  ┌─────────────────────────────┐ │  │
│  │  │         Runner Pod          │ │  │
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

- [Terraform 1.5+](https://www.terraform.io/downloads.html)
- [Helm 3](https://helm.sh/docs/intro/install/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- Azure subscription with appropriate permissions
- Rights to create resources and role assignments in the resource group (for example Owner), and subscription-level role assignment rights unless grant_runner_subscription_reader = false (see "Subscription-level permissions" below)

### Image Delivery & Network Requirements

The Runner image for this deployment is pulled from `matillion.azurecr.io/cloud-agent` — a Matillion-operated public Azure Container Registry with anonymous pull. Your environment must have network access to that registry — via open egress, a whitelisted egress path, or a customer-managed private mirror for zero-egress environments.

See [Network Requirements for Pulling the Runner Image](../../blogs/runner-image-pull-network-requirements.md) for supported network patterns, including the customer-managed ACR + Private Endpoint pattern and ACR Artifact Cache as a managed alternative.

### Required Azure Permissions

```bash
# Login to Azure
az login

# Set subscription
az account set --subscription "your-subscription-id"

# Verify permissions
az role assignment list --assignee $(az account show --query user.name -o tsv)
```

#### Subscription-level permissions

By default the deployment grants the runner's managed identity Reader on the whole subscription (`runner_subscription_reader_role` in `modules/azure/aks`). Because of that grant, whoever runs Terraform needs `Microsoft.Authorization/roleAssignments/read` at subscription scope to plan an existing deployment and `Microsoft.Authorization/roleAssignments/write` at subscription scope to apply. Without them, plan fails with `403 AuthorizationFailed`, or apply fails on this resource after the cluster and the other resources have been created.

An operator whose rights end at the resource group sets `grant_runner_subscription_reader = false`. The deployment then creates no subscription-scope assignment. The other role assignments are on the Key Vault and storage account in the resource group, so the operator still needs to write role assignments there (for example Owner on the resource group).

The runner logs in with `az login --identity --allow-no-subscriptions`. Without the grant it was tested for login, Key Vault read, blob read and write and the Agent Gateway connection. Running pipelines without the grant has not been tested.

Upgrading: with the default (`true`) an existing deployment sees no plan change. Setting `false` on an existing deployment destroys that one role assignment, which needs `Microsoft.Authorization/roleAssignments/delete` at subscription scope for that apply. Run `terraform plan` and check that `module.aks.azurerm_role_assignment.runner_subscription_reader_role[0]` is the only resource destroyed.

```hcl
grant_runner_subscription_reader = false
```

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd agent-deployment/runner/azure/aks
```

### 2. Configure Variables

The resource group must already exist: Terraform references it and does not create it. Create it with:

```bash
az group create --name matillion-runner-rg --location eastus --tags Environment=production Owner=data-team
```

Create `terraform.tfvars`:

```hcl
# Azure Configuration
azure_subscription_id = "12345678-1234-1234-1234-123456789012"
azure_tenant_id       = "your-azure-tenant-id"
resource_group_name   = "matillion-runner-rg"
location              = "eastus"
name                  = "matillion-runner"

# AKS Cluster Configuration
vm_size              = "Standard_D4s_v4" # 4 vCPU, 16GB RAM
node_disk_size       = 250               # GB
desired_node_count   = 3                 # Initial node count
is_private_cluster   = false             # Public for testing
authorized_ip_ranges = ["0.0.0.0/0"]     # Restrict in production

# Kubernetes namespace the runner is installed into. Must equal the namespace
# passed to `helm install`; the workload identity federated credentials are bound
# to it. Leave as matillion unless you install the chart elsewhere.
namespace = "matillion"

# Required: tags has no default
tags = {
  Environment = "production"
  Project     = "matillion-runner"
  Owner       = "data-team"
}
```

`namespace` must equal the namespace used in `helm install` below; the workload identity federated credentials are bound to it.

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review deployment plan
terraform plan

# Deploy infrastructure
terraform apply
```

### 4. Install the runner with Helm

Terraform creates the cluster, identities and Key Vault but does not install the runner chart. Install it with Helm.

Get cluster credentials, still in `runner/azure/aks`. The `k8s_access` output prints the full `az aks get-credentials` command:

```bash
eval "$(terraform output -raw k8s_access)"
```

From the repository root (`cd ../../..`), copy the Azure values file, fill in the values below, then install:

```bash
cp runner/helm/runner/values-azure.yaml my-values.yaml
# edit my-values.yaml
helm install matillion-runner ./runner/helm/runner --namespace matillion --create-namespace -f my-values.yaml
```

| Value | Where it comes from |
|---|---|
| `config.oauthClientId` | Matillion Hub |
| `config.oauthClientSecret` | Matillion Hub |
| `dpcAgent.dpcAgent.env.accountId` | Matillion Hub |
| `dpcAgent.dpcAgent.env.agentId` | Matillion Hub |
| `dpcAgent.dpcAgent.env.matillionRegion` | Matillion Hub |
| `dpcAgent.dpcAgent.env.defaultKeyvault` | `terraform output -raw key_vault_name`, run in `runner/azure/aks` |
| `azure.subscriptionId` | `az account show --query id -o tsv` |
| `azure.workloadIdentity.clientId` | `terraform output -raw k8s_workload_identity_client_id`, run in `runner/azure/aks`. The chart writes it to the `azure.workload.identity/client-id` annotation on the runner service account. |

`my-values.yaml` holds the OAuth client secret. Do not commit it: keep it outside the repository or add its name to `.gitignore` before creating it.

The namespace is `matillion`, the default of the `namespace` variable. To install into another namespace, set `namespace` in `terraform.tfvars` and run `terraform apply` first, because the federated credentials are bound to it. If the chart is installed into a namespace that does not match, the pod fails its token exchange with an MSAL managed identity error and does not become ready.

### 5. Verify Deployment

Run from `runner/azure/aks`:

```bash
# Get AKS credentials
az aks get-credentials --resource-group matillion-runner-rg --name $(terraform output -raw cluster_name)

# Check runner pods
kubectl get pods -n matillion

# Check metrics endpoint
kubectl port-forward -n matillion deployment/matillion-runner-app 8080:8080
curl http://localhost:8080/actuator/prometheus
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
runner_replicas = 1
vm_size = "Standard_D2s_v4"
```

#### Production Environment
```hcl
desired_node_count = 5
runner_replicas = 3
vm_size = "Standard_D8s_v4"
node_disk_size = 500

# Spread nodes across availability zones. Without this the pool is zone-unaware
# and every node — so every runner replica — can land in a single zone.
node_pool_zones = ["1", "2", "3"]

# Staging storage in more than one zone, to match.
storage_account_replication_type = "ZRS"
```

### Zone Resilience

Unlike EKS (whose node groups span their subnets' AZs) and GKE (regional
clusters), **an AKS node pool is zone-unaware unless you say otherwise**. Left at
the default, every node and therefore every runner replica can end up in one
availability zone, and a single zone outage takes the whole runner down.

Two layers are needed, and neither works alone:

```hcl
# 1. Terraform — put the nodes in more than one zone.
node_pool_zones = ["1", "2", "3"]
```

```yaml
# 2. Helm — spread the replicas across the zones the nodes now span, and stop a
#    node drain evicting all of them at once.
topologySpread:
  enabled: true
podDisruptionBudget:
  enabled: true
```

Zonal nodes without `topologySpread` still let the scheduler stack every replica
in one zone; `topologySpread` without zonal nodes has no zones to spread across.

⚠️ **Node pool zones are immutable in Azure.** Setting `node_pool_zones` on a
cluster that already exists produces a plan that *replaces* the default node
pool, destroying every node it runs. Do not apply that against a live
deployment — `modules/azure/aks/readme.md` documents the add-a-zonal-pool-and-
drain migration, including why the drain must respect the runner's 12-hour
termination grace period.

## Monitoring Integration

### Prometheus Metrics

The deployment automatically includes metrics collection:

```yaml
# Prometheus annotations (automatically applied)
prometheus.io/scrape: "true"
prometheus.io/port: "8080"
prometheus.io/path: "/actuator/prometheus"
```

Runner 12.150.3 or later also serves OpenTelemetry metrics on
`:9464/metrics`, which the bundled Prometheus scrapes as a second job. See
[Runner Metrics: Moving to the OpenTelemetry Endpoint](../../blogs/runner-metrics-migration.md).

Available metrics:
- `app_version_info` - Build information
- `app_agent_status` - Running status (1=running, 0=stopped)
- `app_active_task_count` - Active tasks
- `app_active_request_count` - Active requests
- `app_open_sessions_count` - Open database sessions

### Azure Monitor Integration

Container Insights is off by default. To turn it on, set `enable_container_insights = true` in `terraform.tfvars` and apply. Terraform creates a Log Analytics workspace and connects the cluster to it. The workspace ID and name are the `log_analytics_workspace_id` and `log_analytics_workspace_name` outputs. Data appears in the workspace several minutes after the apply finishes. Ingested data is billed.

The queries below run against the workspace named by the `log_analytics_workspace_name` output.

### Log Analytics Queries

```kusto
// Runner pod logs
ContainerLog
| where Name contains "runner"
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

Terraform creates the Key Vault but does not write the runner's OAuth credentials to it. The chart reads them from `config.oauthClientId` and `config.oauthClientSecret` in `my-values.yaml` (step 4). The vault name is the `key_vault_name` output.

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
az aks nodepool scale --resource-group matillion-runner-rg \
  --cluster-name <cluster-name> --name agentpool2 --node-count 5
```

#### Vertical Scaling (Runner Replicas)

The deployment and container names below assume the Helm release is named `matillion-runner`, as in step 4.

`values-azure.yaml` enables the HPA (`hpa.minReplicas: 2`, `hpa.maxReplicas: 10`), which overrides a `kubectl scale`. Change the floor or ceiling in `my-values.yaml` instead, for example `hpa.minReplicas: 4`, then from the repository root:

```bash
helm upgrade matillion-runner ./runner/helm/runner --namespace matillion -f my-values.yaml
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
az aks upgrade --resource-group matillion-runner-rg \
  --name <cluster-name> --kubernetes-version 1.27.0
```

### Troubleshooting

#### Pod Issues

The deployment and container names below assume the Helm release is named `matillion-runner`, as in step 4.

```bash
# Check pod status
kubectl get pods -n matillion

# View pod logs
kubectl logs -n matillion deployment/matillion-runner-app -c matillion-runner-pods

# Describe pod for events
kubectl describe pod -n matillion <pod-name>
```

#### Network Issues
```bash
# Check service endpoints
kubectl get endpoints -n matillion

# Test internal DNS
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default
```

#### Authentication Issues
```bash
# Check managed identity (run from runner/azure/aks)
az identity list --resource-group "$(terraform output -raw resource_group_name)" \
  --query "[?clientId=='$(terraform output -raw k8s_workload_identity_client_id)']" -o table

# Verify Key Vault access
az keyvault secret list --vault-name <vault-name>
```

## Script runner sizing and scaling

How many sessions a pod holds, how many pods to run, and when to turn on the
HPA are the same on every cloud. They're in
[Sizing the script runner](../helm/README.md#sizing-the-script-runner). This
section covers what is specific to AKS.

- **Pods scale; nodes have to follow.** The default node pool runs the
  cluster autoscaler, between `min_node_count` (at least 2, or one per zone) and
  `max_node_count` (twice `desired_node_count` by default). Script runner and
  agent pods share that pool. A script runner HPA that outgrows the nodes leaves
  pods Pending until the autoscaler adds one, which typically takes a few
  minutes. Set `max_node_count` so that agent `maxReplicas` plus script runner
  `maxReplicas`, each at its size's requests, fit.
- **Each pod's requests have to fit on one node**, after AKS's system
  reservations. On this module's default `vm_size`, `Standard_D4s_v4` (4 vCPU,
  16 GiB), `small` and `medium` fit and **`large` doesn't**: it requests the
  node's entire 4 vCPU and 16 GiB. `xlarge` (8 vCPU, 32 GiB) doesn't fit a
  `Standard_D8s_v4` either. A pod that fits no node stays Pending, and the
  autoscaler can't help because it only adds nodes of the same size. Choose
  `vm_size` one step above the largest size you run.
- **Prometheus namespace.** Set the runner chart's
  `networkPolicy.prometheusNamespace` to the namespace you installed the
  prometheus chart into.

## Cost Optimization

### Right-sizing

Monitor resource usage:
```bash
# CPU and memory usage
kubectl top nodes
kubectl top pods -n matillion
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
terraform destroy
```

`terraform destroy` does not delete the resource group, because you created it in step 2 and Terraform only references it. Check what is left in it:

```bash
az resource list --resource-group matillion-runner-rg -o table
```

Delete the group only if nothing else uses it:

```bash
az group delete --name matillion-runner-rg
```

## Performance Tuning

### Node Configuration

```hcl
# High-performance configuration
vm_size = "Standard_D16s_v4"
node_disk_size = 1000
max_pods = 110  # Per node
```

### Runner Optimization

**AKS** — runner resources are set on the helm chart via `runnerSize` (see `runner/helm/README.md`). Pick the smallest size that fits your peak working set:

| `runnerSize` | Requests | Limits | Recommended AKS node |
|---|---|---|---|
| `small` | 1 vCPU / 4 GiB | 2 vCPU / 4 GiB | `Standard_D2s_v5` |
| `medium` | 2 vCPU / 8 GiB | 4 vCPU / 8 GiB | `Standard_D4s_v5` |
| `large` | 4 vCPU / 16 GiB | 8 vCPU / 16 GiB | `Standard_D8s_v5` |
| `xlarge` | 8 vCPU / 32 GiB | 16 vCPU / 32 GiB | `Standard_D16s_v5` |

```bash
# From the repository root, after step 4
helm upgrade matillion-runner ./runner/helm/runner --namespace matillion -f my-values.yaml --set runnerSize=medium
```

A later `helm upgrade` without `--set runnerSize` resets the size to the value in `my-values.yaml`, so to keep it, set `runnerSize` in `my-values.yaml` instead.

**Container Apps** — Container Apps sets `runner_size` on the Terraform template (see [`container_apps/README.md`](container_apps/README.md)). The size also drives `workload_profile_type` because the Consumption profile won't accept the 1:4 cpu:memory ratio.

## Support

For AKS-specific issues:

1. **Check Azure Status**: [Azure Status Page](https://status.azure.com/)
2. **Review AKS logs**: set `enable_container_insights = true` and use the Log Analytics workspace
3. **Azure Support**: Create support case for platform issues
4. **GitHub Issues**: Report deployment configuration problems

## Additional Resources

- [Azure AKS Documentation](https://docs.microsoft.com/en-us/azure/aks/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure Monitor Container Insights](https://docs.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-overview)
- [AKS Best Practices](https://docs.microsoft.com/en-us/azure/aks/best-practices)