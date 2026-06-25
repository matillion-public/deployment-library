# Matillion Runner Deployment

## Overview

This repository provides multiple deployment methods for the Matillion Data Productivity Cloud (DPC) Runner, supporting **Kubernetes**, **AWS ECS**, **AWS EKS**, **Azure AKS**, **Azure Container Apps**, and **GCP GKE** environments with comprehensive monitoring and observability features.

## Deployment Options

### 1. **Kubernetes with Helm Charts** (Recommended)
- Ready-to-use Helm charts for Kubernetes deployment
- Native Prometheus metrics via the runner's `/actuator/prometheus` endpoint
- Support for AWS EKS (IAM roles) and local/minikube (direct credentials)
- Configurable resource limits and autoscaling
- Security-first approach with non-root containers

### 2. **AWS ECS with Terraform**
- Infrastructure as Code with Terraform modules
- Automated IAM role and secrets management
- ECS Fargate deployment with configurable resources

### 3. **AWS EKS with Terraform**
- Infrastructure as Code with Terraform modules
- Kubernetes deployment on AWS EKS
- Automated IAM role and secrets management
- EKS cluster deployment with configurable node groups

### 4. **Azure AKS with Terraform**
- Infrastructure as Code with Terraform modules
- Managed Identity and Key Vault integration
- Native Prometheus metrics integration
- AKS deployment with configurable VM sizes

### 5. **Azure Container Apps with Terraform**
- Infrastructure as Code with Terraform modules
- Serverless container deployment on Azure
- Managed Identity integration

### 6. **GCP GKE with Terraform**
- Infrastructure as Code with Terraform modules
- Workload Identity for secretless pod authentication to GCP services
- GKE cluster deployment with configurable node pools and machine types
- GCS bucket and Secret Manager integration

## Prerequisites

### For Kubernetes Deployment
- [Helm 3.x](https://helm.sh/docs/intro/install/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- Access to a Kubernetes cluster (EKS, AKS, or local like minikube)
- For AWS: Either IAM roles (EKS) or AWS credentials (local/minikube)
- For Azure: Either Workload Identity or Service Principal credentials

### For AWS ECS Deployment  
- [Terraform](https://www.terraform.io/downloads.html)
- AWS CLI configured with appropriate permissions

### For AWS EKS Deployment
- [Terraform](https://www.terraform.io/downloads.html)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- AWS CLI configured with appropriate permissions
- Access to AWS EKS or permissions to create EKS clusters

### For Azure AKS Deployment
- [Terraform](https://www.terraform.io/downloads.html)
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- Azure subscription with appropriate permissions

### For Azure Container Apps Deployment
- [Terraform](https://www.terraform.io/downloads.html)
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- Azure subscription with appropriate permissions

### For GCP GKE Deployment
- [Terraform](https://www.terraform.io/downloads.html)
- [Google Cloud SDK (`gcloud`)](https://cloud.google.com/sdk/docs/install) configured with credentials (`gcloud auth application-default login`)
- [gke-gcloud-auth-plugin](https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm 3.x](https://helm.sh/docs/intro/install/)
- GCP project with billing enabled and sufficient compute quotas

### Image Delivery & Network Requirements

The Runner image is pulled from `public.ecr.aws/matillion/etl-agent` (AWS deployments), `matillion.azurecr.io/cloud-agent` (Azure deployments), or `us-docker.pkg.dev/maia-492711/maia-runners/maia-runner` (GCP deployments — with `europe-docker.pkg.dev` and `australia-southeast1-docker.pkg.dev` regional equivalents for `eu1` and `au1`). All are public registries. Your environment must have network access to the relevant registry — via open egress, a whitelisted egress path, or a private mirror for zero-egress environments.

See [Network Requirements for Pulling the Runner Image](./blogs/runner-image-pull-network-requirements.md) for the supported network patterns and configuration steps for each.

## Required Container Images

The solution uses the following Docker images across different deployment methods:

### Core Application Images
- **`public.ecr.aws/matillion/etl-agent:current`** - Main Data Productivity Cloud runner image (AWS deployments)
- **`public.ecr.aws/matillion/etl-agent:stable`** - Stable Data Productivity Cloud runner image (AWS deployments)
- **`matillion.azurecr.io/cloud-agent:current`** - Main Data Productivity Cloud runner image (Azure deployments)
- **`matillion.azurecr.io/cloud-agent:stable`** - Stable Data Productivity Cloud runner image (Azure deployments)

> **Note**: The AWS and Azure container image artifacts are still published under their original `etl-agent` / `cloud-agent` / `dpc-agent` names — those registry paths are part of the Matillion artifact contract. GCP deployments use the `maia-runner` image in Google Artifact Registry.

### GCP Images
- **`us-docker.pkg.dev/maia-492711/maia-runners/maia-runner:stable`** — GCP runner image, US region (stable)
- **`us-docker.pkg.dev/maia-492711/maia-runners/maia-runner:current`** — GCP runner image, US region (current)
- **`europe-docker.pkg.dev/maia-492711/maia-runners/maia-runner`** — GCP runner image, EU region
- **`australia-southeast1-docker.pkg.dev/maia-492711/maia-runners/maia-runner`** — GCP runner image, AU region

### Infrastructure Images
- **`curlimages/curl:8.5.0`** - Init container for readiness checks

### Monitoring Stack Images
- **`prom/prometheus:v2.22.0`** - Prometheus server for metrics collection
- **`gcr.io/k8s-staging-prometheus-adapter/prometheus-adapter-amd64:v0.12.0`** - Kubernetes metrics adapter

> **Note**: All images are configured with security best practices including non-root users, dropped capabilities, and resource limits.

## Quick Start

### Kubernetes Deployment

```bash
# Clone the repository
git clone <repository_url>
cd deployment-library

# Create required namespaces
kubectl create namespace matillion
kubectl create namespace prometheus

# Install Prometheus monitoring
helm install prometheus runner/helm/prometheus --namespace prometheus

# Create your values file (choose appropriate template):
# For AWS EKS with environment variables:
cp runner/helm/runner/values-aws.yaml my-values.yaml
# For Azure example:
cp runner/helm/runner/values-azure.yaml my-values.yaml
# For Google Cloud GKE example:
cp runner/helm/runner/values-gcp.yaml my-values.yaml

# Edit my-values.yaml with your configuration

# Install the runner
helm install matillion-runner runner/helm/runner/ \
  --namespace matillion \
  -f my-values.yaml

```

For further details reference: [helm readme](https://github.com/matillion-public/deployment-library/blob/main/runner/helm/README.md)

### AWS ECS Deployment

```bash
# Clone the repository
git clone <repository_url>
cd deployment-library/runner/aws/ecs

# Create your terraform.tfvars file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Deploy the infrastructure
terraform init
terraform plan
terraform apply
```

### AWS EKS Deployment

```bash
# Clone the repository
git clone <repository_url>
cd deployment-library

# Navigate to EKS deployment
cd runner/aws/eks

# Create your terraform.tfvars file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your AWS values

# Deploy EKS cluster and runner
terraform init
terraform plan
terraform apply
```

### Azure AKS Deployment

```bash
# Clone the repository
git clone <repository_url>
cd deployment-library

# Navigate to AKS deployment
cd runner/azure/aks

# Create your terraform.tfvars file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Azure values

# Deploy AKS cluster and runner
terraform init
terraform plan
terraform apply
```

### Azure Container Apps Deployment

```bash
# Clone the repository
git clone <repository_url>
cd deployment-library

# Navigate to Container Apps deployment
cd runner/azure/container_apps

# Create your terraform.tfvars file
cp terraform.example.tfvars terraform.tfvars
# Edit terraform.tfvars with your Azure values

# Deploy Container Apps and runner
terraform init
terraform plan
terraform apply
```

### GCP GKE Deployment

```bash
# Clone the repository
git clone <repository_url>
cd deployment-library

# Navigate to GKE deployment
cd runner/gcp/gke

# Create your terraform.tfvars file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your GCP values

# Deploy GKE cluster and runner infrastructure
terraform init
terraform plan
terraform apply

# Configure kubectl
gcloud container clusters get-credentials $(terraform output -raw cluster_name) \
  --region <region> --project <project-id>

# Deploy the runner with Helm
RELEASE_NAME="matillion-runner"
kubectl create namespace "$RELEASE_NAME"
helm upgrade --install "$RELEASE_NAME" ../../helm/runner \
  --namespace "$RELEASE_NAME" \
  -f ../../helm/runner/values-gcp.yaml
```

## Architecture

### Kubernetes Architecture
```
┌─────────────────┐    ┌─────────────────┐
│   Runner Pod    │    │   Prometheus    │
│  ┌────────────┐ │    │    Scraping     │
│  │   Runner   │◄├────┤                 │
│  │    :8080   │ │    │                 │
│  └────────────┘ │    └─────────────────┘
│                 │  :8080/actuator/prometheus
└─────────────────┘
```

### Components
- **Runner Container**: Main Matillion DPC Runner (with native Prometheus metrics)
- **HPA**: Horizontal Pod Autoscaler for scaling
- **Service**: Kubernetes service for internal communication

### Sizing the HPA target

The HPA scales on **in-flight tasks per agent pod** (`hpa.metrics.target.averageValue`), not CPU/memory. Each agent instance has a **hard cap of 20 concurrent tasks**, so `averageValue` must be ≤ 20. We recommend **15–17**: `15` for proactive scaling (spiky workloads), `16` as a balanced default, `17` for reactive scaling (steady workloads). See [`runner/helm/README.md`](runner/helm/README.md#sizing-the-hpa-target-averagevalue) for the full explainer.

## Metrics and Monitoring

### Native Prometheus Metrics
The runner natively exposes Prometheus-compatible metrics at `/actuator/prometheus`:

- **Runner Status**: Running/Stopped state
- **Runner Connected**: Connection state to the Data Productivity Cloud
- **Active Tasks**: Number of currently executing tasks
- **Active Requests**: Number of active API requests
- **Open Sessions**: Number of open database connections
- **Build Information**: Version, commit hash, build timestamp

### Prometheus Integration
```yaml
# Automatic service discovery with annotations
prometheus.io/scrape: "true"
prometheus.io/port: "8080"
prometheus.io/path: "/actuator/prometheus"
```

## Configuration

### Helm Chart Configuration
Key configuration values in `runner/helm/runner/values.yaml`:

```yaml
dpcAgent:
  dpcAgent:
    env:
      accountId: "YOUR_ACCOUNT_ID"
      agentId: "YOUR_AGENT_ID"
      matillionRegion: "YOUR_REGION"
    image:
      repository: "your-registry/dpc-agent"
      tag: "latest"
  replicas: 2
```

> **Note**: The `dpcAgent.*` values block and `agentId` field map to the upstream Matillion subchart contract — these names are intentionally preserved.

### Terraform Configuration

#### AWS ECS Deployment
For AWS ECS deployment, see the [Terraform documentation](./terraform/README.md) for detailed configuration options.

#### Azure AKS Deployment
Key configuration values in `runner/azure/aks/terraform.tfvars`:

```hcl
# Azure Configuration
azure_subscription_id = "your-subscription-id"
resource_group_name   = "matillion-runner-rg"
location             = "East US"

# Matillion Configuration
agent_id            = "your-agent-id"
account_id          = "your-account-id"
matillion_region    = "us-east-1"
client_id          = "your-client-id"
client_secret      = "your-client-secret"

# AKS Configuration
vm_size            = "Standard_D4s_v4"
node_disk_size     = 250
desired_node_count = 3

# Runner Configuration
runner_replicas = 2
```

> **Note**: `agent_id` is preserved as the input variable name because it maps directly to the Matillion `AGENT_ID` env var that the runner image consumes.

## Development

### Repository Structure
```
deployment-library/
├── runner/
│   ├── aws/eks/                # AWS EKS Terraform deployment
│   ├── azure/aks/              # Azure AKS Terraform deployment
│   ├── gcp/gke/                # GCP GKE Terraform deployment
│   └── helm/                   # Helm charts
│       ├── runner/             # Main runner chart
│       ├── prometheus/         # Prometheus adapter chart
│       └── checks/             # Pre-deployment validation scripts
├── modules/
│   ├── aws/                    # AWS Terraform modules
│   ├── azure/                  # Azure Terraform modules
│   └── gcp/                    # GCP Terraform modules
├── tests/                      # Test suite
│   ├── helm/                   # Helm chart tests
│   ├── integration/            # Integration tests
│   └── values/                 # Test configuration files
├── .github/workflows/          # CI/CD pipelines
└── terraform/                  # Legacy ECS modules
```

### Testing

The repository includes comprehensive testing:

```bash
# Python unit tests for metrics exporter
cd runner/helm/image
pytest test_custom_metrics_exporter.py

# Helm chart tests  
pytest tests/helm/test_runner_chart.py

# Integration tests (requires running metrics exporter)
pytest tests/integration/test_metrics_endpoint.py
```

### CI/CD Pipeline

Automated workflows include:
- **Helm Chart Testing**: Linting, templating, and validation
- **Security Scanning**: Trivy, Checkov, GitLeaks, dependency scanning  
- **Docker Building**: Multi-platform image builds
- **Release Management**: Automated chart releases to GitHub Pages

### Releases

Helm charts are automatically published to: `https://github.com/matillion-public/deployment-library`

```bash
# Add the Helm repository
helm repo add matillion https://github.com/matillion-public/deployment-library
helm repo update

# Install from the repository
helm install my-runner matillion/runner
```

## Additional Documentation

- [Helm Chart Documentation](./runner/helm/README.md)
- [Metrics Exporter Documentation](./runner/helm/image/README.md) 
- [AWS ECS Terraform Modules](./terraform/README.md)
- [Azure AKS Documentation](./runner/azure/README.md)
- [GCP GKE Documentation](./runner/gcp/gke/README.md)
- [Network Requirements for Pulling the Runner Image](./blogs/runner-image-pull-network-requirements.md)
- [Right-sizing Matillion Runners](./blogs/right-sizing-matillion-agents.md) — pick `small` / `medium` / `large` / `xlarge` and what each one means on Fargate, Container Apps and Kubernetes
- [Contributing Guide](./CONTRIBUTING.md)

## Support

For issues and feature requests, please use the [GitHub Issues](../../issues) page.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
