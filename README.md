# Matillion Agent Deployment

## Overview

This repository provides multiple deployment methods for the Matillion Data Productivity Cloud (DPC) Agent, supporting **Kubernetes**, **AWS ECS**, **AWS EKS**, **Azure AKS**, and **Azure Container Apps** environments with comprehensive monitoring and observability features.

## Deployment Options

### 1. **Kubernetes with Helm Charts** (Recommended)
- Ready-to-use Helm charts for Kubernetes deployment
- Built-in metrics collection with Prometheus sidecar
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
- Built-in metrics sidecar with Prometheus integration
- AKS deployment with configurable VM sizes

### 5. **Azure Container Apps with Terraform**
- Infrastructure as Code with Terraform modules
- Serverless container deployment on Azure
- Managed Identity integration
- Auto-scaling and pay-per-use pricing model

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

## Required Container Images

The solution uses the following Docker images across different deployment methods:

### Core Application Images
- **`public.ecr.aws/matillion/etl-agent:current`** - Main Data Productivity Cloud agent (AWS deployments)
- **`public.ecr.aws/matillion/etl-agent:stable`** - Stable Data Productivity Cloud agent (AWS deployments)
- **`matillion.azurecr.io/cloud-agent:current`** - Main Data Productivity Cloud agent (Azure deployments)
- **`matillion.azurecr.io/cloud-agent:stable`** - Stable Data Productivity Cloud agent (Azure deployments)
- **`brbajematillion/metrics-sidecar:latest`** - Custom metrics exporter sidecar

### Infrastructure Images
- **`curlimages/curl:8.5.0`** - Init container for readiness checks
- **`python:3.12-alpine`** - Base image for building metrics exporter

### Monitoring Stack Images
- **`prom/prometheus:v2.22.0`** - Prometheus server for metrics collection
- **`gcr.io/k8s-staging-prometheus-adapter/prometheus-adapter-amd64:v0.12.0`** - Kubernetes metrics adapter

> **Note**: All images are configured with security best practices including non-root users, dropped capabilities, and resource limits.

## Quick Start

### Kubernetes Deployment

```bash
# Clone the repository
git clone <repository_url>
cd agent-deployment

# Create required namespaces
kubectl create namespace matillion
kubectl create namespace prometheus

# Install Prometheus monitoring
helm install prometheus agent/helm/prometheus --namespace prometheus

# Create your values file (choose appropriate template):
# For AWS EKS with environment variables:
cp agent/helm/agent/test-values.yaml my-values.yaml
# For AWS local/minikube or direct configuration:
cp agent/helm/agent/values.yaml my-values.yaml
# For Azure example:
cp agent/helm/agent/local.yaml my-values.yaml

# Edit my-values.yaml with your configuration

# Install the agent
helm install matillion-agent agent/helm/agent/ \
  --namespace matillion \
  -f my-values.yaml
```

### AWS ECS Deployment

```bash
# Clone the repository
git clone <repository_url>
cd agent-deployment

# Create your terraform.tfvars file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Deploy the infrastructure
./deploy.sh
```

### AWS EKS Deployment

```bash
# Clone the repository
git clone <repository_url>
cd agent-deployment

# Navigate to EKS deployment
cd agent/aws/eks

# Create your terraform.tfvars file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your AWS values

# Deploy EKS cluster and agent
terraform init
terraform plan
terraform apply
```

### Azure AKS Deployment

```bash
# Clone the repository
git clone <repository_url>
cd agent-deployment

# Navigate to AKS deployment
cd agent/azure/aks

# Create your terraform.tfvars file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Azure values

# Deploy AKS cluster and agent
terraform init
terraform plan
terraform apply
```

### Azure Container Apps Deployment

```bash
# Clone the repository
git clone <repository_url>
cd agent-deployment

# Navigate to Container Apps deployment
cd agent/azure/container_apps

# Create your terraform.tfvars file
cp terraform.example.tfvars terraform.tfvars
# Edit terraform.tfvars with your Azure values

# Deploy Container Apps and agent
terraform init
terraform plan
terraform apply
```

## Architecture

### Kubernetes Architecture
```
┌─────────────────┐    ┌─────────────────┐
│   Agent Pod     │    │  Prometheus     │
│  ┌────────────┐ │    │   Scraping      │
│  │    Agent   │ │    │                 │
│  └────────────┘ │    └─────────────────┘
│  ┌────────────┐ │           │
│  │  Metrics   │◄├───────────┘
│  │  Sidecar   │ │  :8000/metrics
│  └────────────┘ │
└─────────────────┘
```

### Components
- **Agent Container**: Main Matillion DPC Agent
- **Metrics Sidecar**: Prometheus-compatible metrics exporter
- **HPA**: Horizontal Pod Autoscaler for scaling
- **Service**: Kubernetes service for internal communication

## Metrics and Monitoring

### Metrics Sidecar
The Kubernetes deployment includes a **metrics exporter sidecar** that provides Prometheus-compatible metrics:

- **Agent Status**: Running/Stopped state
- **Active Tasks**: Number of currently executing tasks
- **Active Requests**: Number of active API requests
- **Open Sessions**: Number of open database connections
- **Build Information**: Version, commit hash, build timestamp

### Prometheus Integration
```yaml
# Automatic service discovery with annotations
prometheus.io/scrape: "true"
prometheus.io/port: "8000" 
prometheus.io/path: "/metrics"
```

## Configuration

### Helm Chart Configuration
Key configuration values in `agent/helm/agent/values.yaml`:

```yaml
dpcAgent:
  dpcAgent:
    env:
      accountId: "YOUR_ACCOUNT_ID"
      agentId: "YOUR_AGENT_ID" 
      matillionRegion: "YOUR_REGION"
    image:
      repository: "your-registry/agent"
      tag: "latest"
  metricsExporter:
    image:
      repository: "brbajematillion/metrics-sidecar"
      tag: "latest"
  replicas: 2
```

### Terraform Configuration

#### AWS ECS Deployment
For AWS ECS deployment, see the [Terraform documentation](./terraform/README.md) for detailed configuration options.

#### Azure AKS Deployment
Key configuration values in `agent/azure/aks/terraform.tfvars`:

```hcl
# Azure Configuration
azure_subscription_id = "your-subscription-id"
resource_group_name   = "matillion-agent-rg"
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

# Agent Configuration
agent_replicas = 2
metrics_exporter_image_repository = "brbajematillion/metrics-sidecar"
metrics_exporter_image_tag = "latest"
```

## Development

### Repository Structure
```
poc-agent-deployment/
├── agent/
│   ├── azure/aks/              # Azure AKS Terraform deployment
│   ├── aws/eks/                # AWS EKS Terraform deployment  
│   └── helm/                   # Helm charts
│       ├── agent/              # Main agent chart
│       ├── prometheus/         # Prometheus adapter chart
│       └── image/              # Metrics sidecar Docker image
├── modules/
│   ├── azure/                  # Azure Terraform modules
│   └── aws/                    # AWS Terraform modules
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
cd agent/helm/image
pytest test_custom_metrics_exporter.py

# Helm chart tests  
pytest tests/helm/test_agent_chart.py

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

Helm charts are automatically published to: `https://matillion.github.io/poc-agent-deployment/`

```bash
# Add the Helm repository
helm repo add matillion https://matillion.github.io/poc-agent-deployment/
helm repo update

# Install from the repository
helm install my-agent matillion/agent
```

## Additional Documentation

- [Helm Chart Documentation](./agent/helm/README.md)
- [Metrics Exporter Documentation](./agent/helm/image/README.md) 
- [AWS ECS Terraform Modules](./terraform/README.md)
- [Azure AKS Documentation](./agent/azure/README.md)
- [Contributing Guide](./CONTRIBUTING.md)

## Support

For issues and feature requests, please use the [GitHub Issues](../../issues) page.

## License

This project is licensed under the MIT License - see the LICENSE file for details.