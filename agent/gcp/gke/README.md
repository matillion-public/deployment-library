# GCP GKE Deployment for Matillion Agent

This directory contains Terraform configurations for deploying the Matillion DPC Agent using Google Kubernetes Engine (GKE) — Google Cloud's managed Kubernetes service.

## Overview

GKE deployment provides:
- **Managed Kubernetes Control Plane**: Google handles the API server, etcd, and control-plane components
- **Workload Identity**: Keyless authentication from pods to GCP services (Secret Manager, GCS)
- **Auto-scaling**: Horizontal Pod Autoscaler (HPA) and cluster autoscaler on the node pool
- **Private Nodes**: Nodes with no external IPs, egress via Cloud NAT
- **Google Cloud Monitoring**: Native integration with Cloud Logging and Cloud Monitoring

## Architecture

```
┌───────────────────────────────────────────────────────────────────┐
│                         GCP Project                               │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │                      GKE Cluster                             │ │
│  │  ┌─────────────────────────────────────────────────────────┐ │ │
│  │  │                 Control Plane                           │ │ │
│  │  │           (Managed by Google)                           │ │ │
│  │  └─────────────────────────────────────────────────────────┘ │ │
│  │  ┌─────────────────────────────────────────────────────────┐ │ │
│  │  │                  Node Pool                              │ │ │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │ │ │
│  │  │  │   Node 1    │  │   Node 2    │  │   Node N    │     │ │ │
│  │  │  │ ┌─────────┐ │  │ ┌─────────┐ │  │ ┌─────────┐ │     │ │ │
│  │  │  │ │  Agent  │ │  │ │  Agent  │ │  │ │  Agent  │ │     │ │ │
│  │  │  │ │   Pod   │ │  │ │   Pod   │ │  │ │   Pod   │ │     │ │ │
│  │  │  │ └─────────┘ │  │ └─────────┘ │  │ └─────────┘ │     │ │ │
│  │  │  └─────────────┘  └─────────────┘  └─────────────┘     │ │ │
│  │  └─────────────────────────────────────────────────────────┘ │ │
│  └──────────────────────────────────────────────────────────────┘ │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │                    Supporting Services                       │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │ │
│  │  │   Secret    │  │     GCS     │  │   Cloud     │          │ │
│  │  │  Manager    │  │   Bucket    │  │  Monitoring │          │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘          │ │
│  └──────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Required Tools
- [Terraform 1.0+](https://www.terraform.io/downloads.html)
- [Google Cloud SDK (`gcloud`)](https://cloud.google.com/sdk/docs/install) configured with appropriate permissions
- [kubectl](https://kubernetes.io/docs/tasks/tools/) for cluster management
- [Helm 3.0+](https://helm.sh/docs/intro/install/) for application deployment

### GCP Project Requirements
- Valid GCP project with billing enabled
- The following APIs enabled:
  ```bash
  gcloud services enable container.googleapis.com
  gcloud services enable compute.googleapis.com
  gcloud services enable secretmanager.googleapis.com
  gcloud services enable storage.googleapis.com
  gcloud services enable iam.googleapis.com
  ```

### Required GCP Permissions

```bash
# Authenticate with GCP
gcloud auth application-default login

# Verify identity
gcloud auth list
```

Required IAM roles for the Terraform runner:
- `roles/container.admin` — GKE cluster management
- `roles/compute.networkAdmin` — VPC and subnet management
- `roles/iam.serviceAccountAdmin` — Service account creation
- `roles/iam.serviceAccountKeyAdmin` — Workload Identity bindings
- `roles/storage.admin` — GCS bucket management
- `roles/secretmanager.admin` — Secret Manager management
- `roles/resourcemanager.projectIamAdmin` — IAM bindings

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd deployment-library/agent/gcp/gke
```

### 2. Enable Required APIs

```bash
gcloud services enable \
  container.googleapis.com \
  compute.googleapis.com \
  secretmanager.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  --project=<your-project-id>
```

### 3. Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

Minimum required values:
```hcl
project_id = "your-gcp-project-id"
region     = "us-central1"
name       = "matillion-agent"

labels = {
  environment = "production"
  project     = "matillion-agent"
}
```

### 4. Deploy GKE Infrastructure

```bash
# Initialise Terraform
terraform init

# Review deployment plan
terraform plan

# Deploy GKE cluster and supporting infrastructure
terraform apply
```

### 5. Configure kubectl Access

```bash
# Use the command from Terraform output
terraform output -raw auth_config_command | bash

# Verify cluster access
kubectl get nodes
```

### 6. Deploy Matillion Agent with Helm

```bash
# Navigate to the Helm chart directory
cd ../../helm/agent

# Create the agent namespace (should match the `name` Terraform variable)
kubectl create namespace matillion-agent

# Install using the GCP values file
helm install matillion-agent . \
  --namespace matillion-agent \
  --values values-gcp.yaml \
  --set gcp.workloadIdentity.serviceAccountEmail="$(cd ../../../agent/gcp/gke && terraform output -raw agent_workload_sa_email)" \
  --set config.oauthClientId="<your-client-id>" \
  --set config.oauthClientSecret="<your-client-secret>" \
  --set dpcAgent.dpcAgent.env.accountId="<matillion-account-id>" \
  --set dpcAgent.dpcAgent.env.agentId="<matillion-agent-id>" \
  --set dpcAgent.dpcAgent.env.matillionRegion="<matillion-region>"
```

### 7. Verify Deployment

```bash
# Check pod status
kubectl get pods -n matillion-agent

# View pod logs
kubectl logs -l app.kubernetes.io/name=matillion-agent -n matillion-agent

# Check HPA status
kubectl get hpa -n matillion-agent
```

## Configuration Options

### GKE Cluster Configuration

#### Development Environment
```hcl
desired_node_count   = 2
machine_type         = "e2-standard-4"
is_private_cluster   = false
enable_cloud_nat     = false
authorized_ip_ranges = ["<your-office-ip>/32"]
```

#### Production Environment
```hcl
desired_node_count     = 3
machine_type           = "n2-standard-4"
is_private_cluster     = true
enable_cloud_nat       = true          # Required for private nodes
authorized_ip_ranges   = ["10.0.0.0/8", "203.0.113.0/24"]
master_ipv4_cidr_block = "172.16.0.0/28"
```

### Workload Identity

GKE Workload Identity allows pods to authenticate to GCP APIs without managing service account keys. The Terraform module:

1. Creates a GCP Service Account (`agent_workload_sa`)
2. Binds it to the Kubernetes Service Account created by Helm (`<name>/<name>-sa`)
3. Grants the GCP SA access to Secret Manager and GCS

The Helm chart adds the required annotation to the Kubernetes Service Account:
```yaml
annotations:
  iam.gke.io/gcp-service-account: <gcp-sa-email>
```

Pass the SA email from Terraform output:
```bash
terraform output -raw agent_workload_sa_email
```

### Networking

#### Private Cluster (Recommended for Production)
```hcl
is_private_cluster     = true
enable_cloud_nat       = true   # Required so private nodes can pull images
master_ipv4_cidr_block = "172.16.0.0/28"
authorized_ip_ranges   = ["10.0.0.0/8"]
```

Network layout:
```
VPC
├── Subnet 0 (10.0.1.0/24) — GKE nodes
│   ├── Secondary range: pods-0 (10.1.0.0/16)
│   └── Secondary range: services-0 (10.10.0.0/20)
├── Subnet 1 (10.0.2.0/24)
│   ├── Secondary range: pods-1 (10.2.0.0/16)
│   └── Secondary range: services-1 (10.11.0.0/20)
└── Cloud NAT (static egress IP)
```

#### Public Cluster (Development Only)
```hcl
is_private_cluster = false
enable_cloud_nat   = false
```

## Outputs

After `terraform apply`, the following outputs are available:

| Output | Description |
|--------|-------------|
| `cluster_name` | GKE cluster name |
| `auth_config_command` | `gcloud` command to configure `kubectl` |
| `agent_workload_sa_email` | GCP SA email for Helm `gcp.workloadIdentity.serviceAccountEmail` |
| `gcs_bucket_name` | GCS bucket for agent staging storage |
| `secret_manager_secret_id` | Secret Manager secret ID |
| `nat_ip` | Static Cloud NAT egress IP (if `enable_cloud_nat = true`) |

## Monitoring and Observability

GKE integrates with Google Cloud Monitoring and Logging out of the box.

```bash
# View cluster logs in Cloud Logging
gcloud logging read "resource.type=k8s_container AND resource.labels.cluster_name=<cluster-name>" \
  --project=<project-id> --limit=50

# View metrics in Cloud Monitoring
gcloud monitoring dashboards list --project=<project-id>
```

### Prometheus Integration (Optional)

```bash
cd ../../helm/prometheus

helm install prometheus . \
  --create-namespace \
  --namespace monitoring

kubectl port-forward -n monitoring svc/prometheus-server 9090:80
```

## Security

### Shielded Nodes

Nodes are provisioned with Secure Boot and integrity monitoring enabled by default.

### Network Policies

Enable network policies in the Helm values:
```yaml
networkPolicy:
  enabled: true
  prometheusNamespace: monitoring
  allowHttp: true
```

### Secrets Management

OAuth credentials are stored as Kubernetes secrets. The GCP Secret Manager secret provisioned by Terraform can be used for additional application secrets.

```bash
# Store a secret value
gcloud secrets versions add <secret-id> --data-file=<file>

# Access from the agent workload SA (already has secretAccessor role)
```

## Operations

### Scaling

```bash
# Manual pod scaling
kubectl scale deployment matillion-agent-app --replicas=5 -n matillion-agent

# View HPA status
kubectl get hpa -n matillion-agent
kubectl describe hpa matillion-agent-hpa -n matillion-agent
```

### Application Updates

```bash
# Rolling update
helm upgrade matillion-agent . \
  --namespace matillion-agent \
  --reuse-values \
  --set dpcAgent.dpcAgent.image.tag="v2.0.0"

# Monitor rollout
kubectl rollout status deployment/matillion-agent-app -n matillion-agent
```

### Troubleshooting

```bash
# Check pod status and events
kubectl describe pod <pod-name> -n matillion-agent

# View pod logs
kubectl logs <pod-name> -c matillion-agent-pods -n matillion-agent

# Check Workload Identity is working
kubectl exec -it <pod-name> -n matillion-agent -- \
  curl -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email"
```

## Cleanup

```bash
# Uninstall Helm release
helm uninstall matillion-agent -n matillion-agent
kubectl delete namespace matillion-agent

# Destroy infrastructure
terraform destroy
```
