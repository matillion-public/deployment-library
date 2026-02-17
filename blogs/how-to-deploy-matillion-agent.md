# How to Deploy the Matillion Agent: Complete Guide

This comprehensive guide walks you through deploying the Matillion Data Productivity Cloud (DPC) Agent using the five supported methods: Kubernetes with Helm, AWS ECS with Terraform, Azure AKS with Terraform, AWS EKS with Terraform, and Azure Container Instances (ACI) with Terraform.

## Prerequisites

Before starting any deployment, ensure you have:

- **Matillion Account**: Agent ID, Account ID, and region information
- **Container Registry Access**: Pull permissions for required images
- **Target Platform Tools**: Depending on your chosen deployment method

## Deployment Method 1: Kubernetes with Helm (Recommended)

### Prerequisites
- Helm 3.x installed
- kubectl configured for your cluster
- Kubernetes cluster with at least 2 CPU cores and 4GB RAM available
- For AWS: Either IAM roles (EKS) or AWS credentials (local/minikube)
- For Azure: Either Workload Identity or Service Principal credentials

### Step 1: Clone the Repository
```bash
git clone <repository_url>
cd agent-deployment
```

### Step 2: Create Namespaces
```bash
# Create required namespaces
kubectl create namespace matillion
kubectl create namespace prometheus

# Install Prometheus monitoring
helm install prometheus agent/helm/prometheus --namespace prometheus
```

### Step 3: Configure Values
Choose the appropriate values template based on your deployment:

```bash
# For AWS EKS with IAM roles (recommended for production)
cp agent/helm/agent/test-values.yaml custom-values.yaml
# Set environment variables for sensitive data
export MATILLION_AGENT_CLIENT_ID="your-client-id"
export MATILLION_AGENT_CLIENT_SECRET="your-client-secret"
export MATILLION_AGENT_ROLE_ARN="arn:aws:iam::123456789012:role/your-role"

# For local/minikube with direct AWS credentials
cp agent/helm/agent/values.yaml custom-values.yaml
# Edit to enable aws.local.enabled=true and add credentials

# For Azure deployments (example)
cp agent/helm/agent/local.yaml custom-values.yaml
```

### Step 4: Install the Agent
```bash
# For deployments with environment variables
envsubst < custom-values.yaml | helm install matillion-agent agent/helm/agent/ \
  --namespace matillion \
  -f -

# For deployments with direct configuration
helm install matillion-agent agent/helm/agent/ \
  --namespace matillion \
  -f custom-values.yaml
```

### Step 5: Verify Deployment
```bash
# Check pod status
kubectl get pods -n matillion -l app.kubernetes.io/name=agent

# Check metrics endpoint
kubectl port-forward -n matillion deployment/matillion-agent 8000:8000
curl http://localhost:8000/metrics

# Verify Prometheus is scraping metrics
kubectl port-forward -n prometheus svc/prometheus 9090:9090
# Visit http://localhost:9090/targets to see discovered targets
```

### Key Configuration Options

```yaml
# Scaling configuration
replicas: 2

# Agent configuration
cloudProvider: "aws"  # or "azure"
config:
  oauthClientId: "YOUR_CLIENT_ID"
  oauthClientSecret: "YOUR_CLIENT_SECRET"

# For AWS EKS with IAM roles
serviceAccount:
  roleArn: "arn:aws:iam::123456789012:role/matillion-agent"

# For AWS local/minikube with direct credentials
aws:
  local:
    enabled: true
    region: "us-west-2"
    accessKeyId: "YOUR_ACCESS_KEY_ID"
    secretAccessKey: "YOUR_SECRET_ACCESS_KEY"

# Agent configuration
dpcAgent:
  dpcAgent:
    env:
      accountId: "YOUR_ACCOUNT_ID"
      agentId: "YOUR_AGENT_ID"
      matillionRegion: "YOUR_REGION"
    image:
      repository: "public.ecr.aws/matillion/etl-agent"
      tag: "current"
    resources:
      requests:
        memory: "2Gi"
        cpu: "1000m"
      limits:
        memory: "4Gi"
        cpu: "2000m"

# Autoscaling
hpa:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```

## Deployment Method 2: AWS ECS with Terraform

### Prerequisites
- Terraform installed
- AWS CLI configured with appropriate permissions
- AWS VPC and subnets available

### Step 1: Setup Terraform Configuration
```bash
cd agent/aws/ecs
cp terraform.tfvars.example terraform.tfvars
```

### Step 2: Configure Variables
Edit `terraform.tfvars`:

```hcl
# AWS Configuration
aws_region = "YOUR_REGION"
vpc_id     = "YOUR_VPC_ID"
subnet_ids = ["YOUR_SUBNET_IDS"]

# Matillion Configuration
agent_id         = "YOUR_AGENT_ID"
account_id       = "YOUR_ACCOUNT_ID"
matillion_region = "YOUR_REGION"

# ECS Configuration
desired_count = 2
cpu           = 2048
memory        = 4096
```

### Step 3: Deploy Infrastructure
```bash
terraform init
terraform plan
terraform apply
```

### Step 4: Verify Deployment
```bash
# Check ECS service status
aws ecs describe-services --cluster matillion-agent-cluster --services matillion-agent-service

# Check CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix "/ecs/matillion-agent"
```

## Deployment Method 3: Azure AKS with Terraform

### Prerequisites
- Terraform installed
- Azure CLI installed and authenticated
- Azure subscription with appropriate permissions

### Step 1: Setup Azure Authentication
```bash
az login
az account set --subscription "your-subscription-id"
```

### Step 2: Create Service Principal for Key Vault
```bash
az ad sp create-for-rbac --name "matillion-agent-keyvault-sp" \
  --role "Key Vault Secrets User" \
  --scopes "/subscriptions/{subscription-id}/resourceGroups/{resource-group-name}"
```

### Step 3: Configure Terraform Variables
```bash
cd agent/azure/aks
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
# Azure Configuration
azure_subscription_id = "your-subscription-id"
resource_group_name   = "matillion-agent-rg"
location             = "East US"

# Matillion Configuration
agent_id            = "your-agent-id"
account_id          = "your-account-id"
matillion_region    = "us-east-1"

# Service Principal for Key Vault
service_principal_client_id = "sp-client-id-from-step-2"
service_principal_secret    = "sp-secret-from-step-2"

# AKS Configuration
vm_size            = "Standard_D4s_v4"
desired_node_count = 3
agent_replicas     = 2
```

### Step 4: Deploy AKS and Agent
```bash
terraform init
terraform plan
terraform apply
```

### Step 5: Configure kubectl
```bash
az aks get-credentials --resource-group matillion-agent-rg --name matillion-agent-aks
kubectl get pods -n default
```

## Deployment Method 4: AWS EKS with Terraform

### Prerequisites
- Terraform installed
- AWS CLI configured with appropriate permissions
- kubectl installed for cluster management

### Step 1: Setup Terraform Configuration
```bash
cd agent/aws/eks
cp terraform.tfvars.example terraform.tfvars
```

### Step 2: Configure Variables
Edit `terraform.tfvars`:

```hcl
# AWS Configuration
aws_region = "YOUR_REGION"
cluster_name = "matillion-agent-eks"

# Matillion Configuration
agent_id         = "YOUR_AGENT_ID"
account_id       = "YOUR_ACCOUNT_ID"
matillion_region = "YOUR_REGION"

# EKS Configuration
kubernetes_version = "1.28"
node_group_instance_types = ["t3.medium"]
desired_size = 2
max_size = 10
min_size = 1

# Agent Configuration
agent_replicas = 2
cpu_request = "1000m"
memory_request = "2Gi"
cpu_limit = "2000m"
memory_limit = "4Gi"
```

### Step 3: Deploy EKS Cluster and Agent
```bash
terraform init
terraform plan
terraform apply
```

### Step 4: Configure kubectl and Verify
```bash
# Configure kubectl
aws eks update-kubeconfig --region YOUR_REGION --name matillion-agent-eks

# Verify deployment
kubectl get pods -n matillion -l app.kubernetes.io/name=matillion-agent
kubectl get nodes
```

## Deployment Method 5: Azure Container Instances (ACI) with Terraform

### Prerequisites
- Terraform installed
- Azure CLI installed and authenticated
- Azure subscription with appropriate permissions

### Step 1: Setup Azure Authentication
```bash
az login
az account set --subscription "your-subscription-id"
```

### Step 2: Configure Terraform Variables
```bash
cd agent/azure/aci
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
# Azure Configuration
azure_subscription_id = "your-subscription-id"
resource_group_name   = "matillion-agent-rg"
location             = "East US"

# Matillion Configuration
agent_id            = "your-agent-id"
account_id          = "your-account-id"
matillion_region    = "us-east-1"

# ACI Configuration
container_group_name = "matillion-agent-aci"
cpu_cores           = 2
memory_gb           = 4
replica_count       = 2

# Container Configuration
container_image = "your-registry/cloud-agent:latest"
restart_policy  = "Always"
```

### Step 3: Deploy ACI Container Group
```bash
terraform init
terraform plan
terraform apply
```

### Step 4: Verify Deployment
```bash
# Check container group status
az container show --resource-group matillion-agent-rg --name matillion-agent-aci

# View container logs
az container logs --resource-group matillion-agent-rg --name matillion-agent-aci --container-name matillion-agent
```

## Post-Deployment Configuration

### Setting Up Monitoring

All deployment methods include built-in metrics collection. To set up monitoring:

#### 1. Prometheus Integration
```yaml
# Add to your prometheus.yml
scrape_configs:
  - job_name: 'matillion-agent'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
```

#### 2. Grafana Dashboard
Import the included Grafana dashboard for agent monitoring:
- Agent status and health
- Active tasks and requests
- Resource utilization
- Error rates and response times

### Configuring Autoscaling

#### Kubernetes HPA Configuration
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: matillion-agent-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: matillion-agent
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - pods:
      metric:
        name: app_active_task_count
      target:
        averageValue: "18"
        type: AverageValue
  - pods:
      metric:
        name: app_active_request_count
      target:
        averageValue: "18"
        type: AverageValue
```

## Troubleshooting Common Issues

### Issue 1: Agent Not Starting
**Symptoms**: Pods in CrashLoopBackOff or ECS tasks failing
**Solutions**:
- Verify account ID, agent ID, and region configuration
- Check image pull permissions
- Review container logs for authentication errors

### Issue 2: Metrics Not Available
**Symptoms**: Prometheus scraping fails or /metrics endpoint unreachable
**Solutions**:
- Verify metrics sidecar is running
- Check port 8000 is accessible
- Confirm Prometheus configuration includes correct labels

### Issue 3: High Resource Usage
**Symptoms**: Containers consuming excessive CPU/memory
**Solutions**:
- Review and adjust resource limits
- Enable autoscaling
- Monitor for memory leaks in application logs

### Issue 4: Scaling Issues
**Symptoms**: HPA not scaling or ECS auto scaling not working
**Solutions**:
- Verify metrics server is running (Kubernetes)
- Check CloudWatch metrics are being published (AWS)
- Review scaling policies and thresholds

## Best Practices

### Security
- Use least-privilege IAM roles/managed identities
- Enable network policies to restrict pod-to-pod communication
- Regularly rotate secrets and credentials
- Keep container images updated with security patches

### Performance
- Set appropriate resource requests and limits
- Use persistent volumes for data that needs to survive restarts
- Monitor and tune garbage collection settings
- Implement graceful shutdown procedures

### Monitoring
- Set up alerts for agent health and performance metrics
- Monitor data pipeline execution times
- Track resource utilization trends
- Implement log aggregation for centralized monitoring

### Maintenance
- Regularly update agent images
- Test deployments in staging environments
- Document configuration changes
- Maintain backup and disaster recovery procedures

## Next Steps

After successful deployment:

1. **Configure monitoring and alerting** using the built-in metrics
2. **Set up autoscaling** based on your workload patterns
3. **Implement CI/CD pipelines** for automated updates
4. **Review security configurations** and apply additional hardening
5. **Create disaster recovery procedures** for business continuity

For advanced configuration options and troubleshooting, refer to the individual platform documentation in the repository.