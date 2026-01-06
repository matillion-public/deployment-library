# AWS EKS Deployment for Matillion Agent

This directory contains Terraform configurations for deploying the Matillion DPC Agent using Amazon EKS (Elastic Kubernetes Service) - a managed Kubernetes service that provides enterprise-grade security, reliability, and scalability.

## Overview

AWS EKS deployment provides:
- **Managed Kubernetes Control Plane**: AWS handles the Kubernetes API server and etcd
- **Worker Node Flexibility**: Choose from EC2, Fargate, or hybrid deployments
- **Advanced Scaling**: Horizontal Pod Autoscaler (HPA), Vertical Pod Autoscaler (VPA), and Cluster Autoscaler
- **Comprehensive Monitoring**: Native integration with CloudWatch, plus support for Prometheus/Grafana
- **Sidecar Support**: Deploy metrics exporters and other sidecar containers
- **Kubernetes Ecosystem**: Full access to Kubernetes tools and operators

## Architecture

```
┌───────────────────────────────────────────────────────────────────┐
│                           AWS Account                             │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │                      EKS Cluster                             │ |
│  │  ┌─────────────────────────────────────────────────────────┐ │ │
│  │  │                 Control Plane                           │ │ │
│  │  │           (Managed by AWS)                              │ │ │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │ │ │
│  │  │  │ API Server  │  │    etcd     │  │ Controller  │      │ │ │
│  │  │  │             │  │             │  │   Manager   │      │ │ │
│  │  │  └─────────────┘  └─────────────┘  └─────────────┘      │ │ │
│  │  └─────────────────────────────────────────────────────────┘ │ │
│  │  ┌─────────────────────────────────────────────────────────┐ │ │
│  │  │                  Worker Nodes                           │ │ │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │ │ │
│  │  │  │   Node 1    │  │   Node 2    │  │   Node N    │      │ │ │
│  │  │  │ ┌─────────┐ │  │ ┌─────────┐ │  │ ┌─────────┐ │      │ │ │
│  │  │  │ │  Agent  │ │  │ │  Agent  │ │  │ │  Agent  │ │      │ │ │
│  │  │  │ │   Pod   │ │  │ │   Pod   │ │  │ │   Pod   │ │      │ │ │
│  │  │  │ │ ┌─────┐ │ │  │ │ ┌─────┐ │ │  │ │ ┌─────┐ │ │      │ │ │
│  │  │  │ │ │Agent│ │ │  │ │ │Agent│ │ │  │ │ │Agent│ │ │      │ │ │
│  │  │  │ │ └─────┘ │ │  │ │ └─────┘ │ │  │ │ └─────┘ │ │      │ │ │
│  │  │  │ │ ┌─────┐ │ │  │ │ ┌─────┐ │ │  │ │ ┌─────┐ │ │      │ │ │
│  │  │  │ │ │Metrc│ │ │  │ │ │Metrc│ │ │  │ │ │Metrc│ │ │      │ │ │
│  │  │  │ │ │Exprt│ │ │  │ │ │Exprt│ │ │  │ │ │Exprt│ │ │      │ │ │
│  │  │  │ │ └─────┘ │ │  │ │ └─────┘ │ │  │ │ └─────┘ │ │      │ │ │
│  │  │  │ └─────────┘ │  │ └─────────┘ │  │ └─────────┘ │      │ │ │
│  │  │  └─────────────┘  └─────────────┘  └─────────────┘      │ │ │
│  │  └─────────────────────────────────────────────────────────┘ │ │
│  └──────────────────────────────────────────────────────────────┘ │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │                    Supporting Services                       │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │ │
│  │  │   Secrets   │  │   S3 Data   │  │ CloudWatch  │           │ │
│  │  │  Manager    │  │   Storage   │  │  Monitoring │           │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘           │ │
│  └──────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Required Tools
- [Terraform 1.0+](https://www.terraform.io/downloads.html)
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate permissions
- [kubectl](https://kubernetes.io/docs/tasks/tools/) for cluster management
- [Helm 3.0+](https://helm.sh/docs/intro/install/) for application deployment

### AWS Account Requirements
- Valid AWS account with EKS service enabled
- Sufficient EC2 service quotas for worker nodes
- VPC with public/private subnet configuration

### Required AWS Permissions

```bash
# Configure AWS CLI
aws configure

# Verify permissions
aws sts get-caller-identity
```

Required IAM permissions:
- EKS cluster and node group management
- EC2 instance and Auto Scaling group management
- IAM role creation and management
- VPC and networking resource management
- AWS Secrets Manager access
- S3 bucket operations
- CloudWatch logs and monitoring

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd agent-deployment/agent/aws/eks
```

### 2. Configure Variables

Create or edit `terraform.tfvars`:

```hcl
# AWS Configuration
region = "us-east-1"
name   = "matillion-agent-eks"

# EKS Cluster Configuration
desired_node_count    = 3
is_private_cluster    = false
authorized_ip_ranges  = ["0.0.0.0/0"]  # Restrict in production

# Networking Configuration
use_existing_vpc      = false
existing_vpc_id       = ""
cidr_block           = "172.5.0.0/16"
use_existing_subnet   = false
existing_subnet_ids   = []

# Resource Tags
tags = {
  Environment = "production"
  Project     = "matillion-agent"
  Team        = "data-platform"
}
```

### 3. Deploy EKS Infrastructure

```bash
# Initialize Terraform
terraform init

# Review deployment plan
terraform plan

# Deploy EKS cluster and supporting infrastructure
terraform apply
```

### 4. Configure kubectl Access

```bash
# Configure kubectl to access the EKS cluster
aws eks update-kubeconfig --region <your-region> --name <cluster-name>

# Verify cluster access
kubectl get nodes
kubectl get namespaces
```

### 5. Deploy Matillion Agent with Helm

```bash
# Navigate to Helm chart directory
cd ../../helm/agent

# Install the agent using Helm
helm install matillion-agent . \
  --set cloudProvider="aws" \
  --set config.oauthClientId="<your-client-id>" \
  --set config.oauthClientSecret="<your-client-secret>" \
  --set serviceAccount.roleArn="<service-account-role-arn>" \
  --set dpcAgent.dpcAgent.env.accountId="<matillion-account-id>" \
  --set dpcAgent.dpcAgent.env.agentId="<matillion-agent-id>" \
  --set dpcAgent.dpcAgent.env.matillionRegion="<matillion-region>" \
  --set dpcAgent.dpcAgent.image.repository="public.ecr.aws/matillion/etl-agent" \
  --set dpcAgent.dpcAgent.image.tag="current" \
  --set dpcAgent.metricsExporter.image.repository="public.ecr.aws/matillion/metrics-exporter" \
  --set dpcAgent.metricsExporter.image.tag="current"
```

### 6. Verify Deployment

```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=matillion-agent

# View pod logs
kubectl logs -l app.kubernetes.io/name=matillion-agent -c matillion-agent-pods

# Check service status
kubectl get services

# View HPA status (if enabled)
kubectl get hpa
```

## Configuration Options

### EKS Cluster Configuration

#### Development Environment
```hcl
desired_node_count    = 2
is_private_cluster    = false
authorized_ip_ranges  = ["<your-office-ip>/32"]

# Node instance types (managed by module)
# Typically: t3.medium or t3.large for dev
```

#### Production Environment
```hcl
desired_node_count    = 5
is_private_cluster    = true
authorized_ip_ranges  = ["10.0.0.0/8", "172.16.0.0/12"]

# Node instance types (managed by module)
# Typically: m5.large, m5.xlarge, or c5.xlarge for production
```

### Networking Configuration

#### Existing VPC Usage

**IMPORTANT**: When using existing infrastructure with EKS Fargate, you must provide **private subnets** with NAT gateway access. Fargate requires private subnets and will fail to provision if public subnets are provided.

##### Using Existing VPC with Existing Subnets
```hcl
use_existing_vpc      = true
existing_vpc_id       = "vpc-12345678"
use_existing_subnet   = true

# CRITICAL: These MUST be private subnets with NAT gateway access for Fargate
existing_subnet_ids   = [
  "subnet-12345678",  # Private subnet AZ-a (with NAT gateway route)
  "subnet-87654321",  # Private subnet AZ-b (with NAT gateway route)
  "subnet-11111111"   # Private subnet AZ-c (with NAT gateway route)
]
```

**Subnet Requirements for Fargate**:
- Subnets MUST be private (not directly routed to Internet Gateway)
- Subnets MUST have a route to a NAT Gateway for outbound internet access
- Subnets MUST be in at least 2 different availability zones
- Each subnet's route table should have: `0.0.0.0/0` → `nat-xxxxx`

**To verify your subnets meet the requirements**:
```bash
# Check if subnet is private (should NOT have map_public_ip_on_launch)
aws ec2 describe-subnets --subnet-ids subnet-12345678 \
  --query 'Subnets[0].MapPublicIpOnLaunch'

# Check route table has NAT gateway route
ROUTE_TABLE_ID=$(aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=subnet-12345678" \
  --query 'RouteTables[0].RouteTableId' --output text)

aws ec2 describe-route-tables --route-table-ids $ROUTE_TABLE_ID \
  --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`]'
# Should show NatGatewayId, NOT GatewayId (igw-xxxx)
```

##### Using Existing VPC but Creating New Subnets
```hcl
use_existing_vpc      = true
existing_vpc_id       = "vpc-12345678"
use_existing_subnet   = false
cidr_block           = "172.5.0.0/16"  # Should match existing VPC CIDR

# Terraform will create within the existing VPC:
# - 2 public subnets with Internet Gateway access
# - 2 private subnets with NAT Gateway access
# - NAT Gateways and Elastic IPs
# - Route tables for both public and private subnets
```

#### New VPC Creation
```hcl
use_existing_vpc      = false
cidr_block           = "172.5.0.0/16"

# Terraform will create:
# - New VPC with specified CIDR block
# - Internet Gateway
# - 2 public subnets (172.5.0.0/24, 172.5.1.0/24)
# - 2 private subnets (172.5.2.0/24, 172.5.3.0/24)
# - 2 NAT Gateways (one per AZ for high availability)
# - 2 Elastic IPs for NAT Gateways
# - Public route table (routes to Internet Gateway)
# - 2 private route tables (route to respective NAT Gateways)
```

**Network Architecture**:
```
VPC (172.5.0.0/16)
├── Public Subnet 1 (172.5.0.0/24) → Internet Gateway
│   └── NAT Gateway 1
├── Public Subnet 2 (172.5.1.0/24) → Internet Gateway
│   └── NAT Gateway 2
├── Private Subnet 1 (172.5.2.0/24) → NAT Gateway 1 (for Fargate)
└── Private Subnet 2 (172.5.3.0/24) → NAT Gateway 2 (for Fargate)
```

### Agent Configuration with Helm

Create a custom values file (`values-production.yaml`):

```yaml
cloudProvider: "aws"

config:
  oauthClientId: "<your-client-id>"
  oauthClientSecret: "<your-client-secret>"

serviceAccount:
  roleArn: "<service-account-role-arn>"

dpcAgent:
  replicas: 3
  dpcAgent:
    env:
      accountId: <your-matillion-account-id>
      agentId: <your-unique-agent-id>
      matillionRegion: <your-matillion-region>
    image:
      repository: public.ecr.aws/matillion/etl-agent
      tag: "current"
    resources:
      requests:
        cpu: "1"
        memory: 4Gi
      limits:
        cpu: "2"
        memory: 4Gi
  metricsExporter:
    image:
      repository: public.ecr.aws/matillion/metrics-exporter
      tag: "current"
    resources:
      requests:
        cpu: "500m"
        memory: 512Mi
      limits:
        cpu: "1000m"
        memory: 1024Mi

# Horizontal Pod Autoscaler configuration
hpa:
  minReplicas: 2
  maxReplicas: 10
  metrics:
    target:
      averageValue: "70"
      type: AverageValue

# Network security
networkPolicy:
  enabled: true
  allowHttp: true
```

Deploy with custom values:

```bash
helm install matillion-agent . -f values-production.yaml
```

## 📊 Monitoring and Observability

### CloudWatch Integration

EKS provides comprehensive CloudWatch integration:

```bash
# Enable CloudWatch Container Insights
aws eks create-addon \
  --cluster-name <cluster-name> \
  --addon-name aws-for-fluent-bit \
  --addon-version v2.21.0-eksbuild.1

# View cluster logs
aws logs describe-log-groups --log-group-name-prefix "/aws/eks/"
```

### Metrics Collection

The deployment includes a metrics exporter sidecar:

- **Agent Metrics**: Business logic and job execution metrics
- **System Metrics**: CPU, memory, network utilization
- **Kubernetes Metrics**: Pod restarts, resource usage
- **Custom Metrics**: Application-specific metrics for HPA

### Prometheus Integration (Optional)

Deploy Prometheus for advanced monitoring:

```bash
# Navigate to Prometheus Helm chart
cd ../../helm/prometheus

# Install Prometheus stack
helm install prometheus . \
  --create-namespace \
  --namespace monitoring

# Access Prometheus UI (port-forward)
kubectl port-forward -n monitoring svc/prometheus-server 9090:80
```

### Log Aggregation

```bash
# View agent logs
kubectl logs -f deployment/matillion-agent-app -c matillion-agent-pods

# View metrics exporter logs
kubectl logs -f deployment/matillion-agent-app -c metrics-exporter

# Stream all logs
kubectl logs -f -l app.kubernetes.io/name=matillion-agent --all-containers=true
```

## 🔒 Security Configuration

### IAM Roles for Service Accounts (IRSA)

The deployment creates:

#### EKS Service Account Role
- Allows pods to assume AWS IAM roles
- Provides access to AWS services (S3, Secrets Manager)
- Follows principle of least privilege

```bash
# View service account
kubectl describe serviceaccount matillion-agent-sa

# Check role annotation
kubectl get serviceaccount matillion-agent-sa -o yaml
```

### Pod Security Standards

The deployment implements security best practices:

```yaml
# Security context (from deployment template)
securityContext:
  runAsNonRoot: true
  runAsUser: 65534
  runAsGroup: 65534
  fsGroup: 65534
  seccompProfile:
    type: RuntimeDefault

# Container security
containers:
  securityContext:
    allowPrivilegeEscalation: false
    runAsNonRoot: true
    capabilities:
      drop:
        - ALL
```

### Network Policies

When enabled, network policies restrict pod communication:

```yaml
# Enable network policies in values file
networkPolicy:
  enabled: true
  prometheusNamespace: monitoring
  allowHttp: true
```

### Secrets Management

```bash
# OAuth credentials stored in Kubernetes secrets
kubectl get secrets -l app.kubernetes.io/name=matillion-agent

# View secret (base64 encoded)
kubectl describe secret matillion-agent-config
```

## Operations

### Scaling Operations

#### Manual Scaling
```bash
# Scale deployment manually
kubectl scale deployment matillion-agent-app --replicas=5

# Scale cluster nodes (via AWS CLI)
aws eks update-nodegroup-config \
  --cluster-name <cluster-name> \
  --nodegroup-name <nodegroup-name> \
  --scaling-config minSize=3,maxSize=10,desiredSize=5
```

#### Horizontal Pod Autoscaler (HPA)
```bash
# View HPA status
kubectl get hpa

# Describe HPA details
kubectl describe hpa matillion-agent-hpa

# Monitor scaling events
kubectl get events --sort-by=.metadata.creationTimestamp
```

#### Cluster Autoscaler (Optional)
```bash
# Deploy cluster autoscaler
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml

# Configure cluster name
kubectl patch deployment cluster-autoscaler \
  -n kube-system \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"cluster-autoscaler","command":["./cluster-autoscaler","--v=4","--stderrthreshold=info","--cloud-provider=aws","--skip-nodes-with-local-storage=false","--expander=least-waste","--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/<cluster-name>"]}]}}}}'
```

### Application Updates

#### Rolling Updates
```bash
# Update agent image
helm upgrade matillion-agent . \
  --set dpcAgent.dpcAgent.image.tag="v2.0.0" \
  --reuse-values

# Monitor rollout
kubectl rollout status deployment/matillion-agent-app

# View rollout history  
kubectl rollout history deployment/matillion-agent-app
```

#### Rollback Operations
```bash
# Rollback to previous version
kubectl rollout undo deployment/matillion-agent-app

# Rollback to specific revision
kubectl rollout undo deployment/matillion-agent-app --to-revision=2
```

### Troubleshooting

#### Cluster Issues
```bash
# Check cluster status
aws eks describe-cluster --name <cluster-name>

# View cluster events
kubectl get events --sort-by=.metadata.creationTimestamp

# Check node status
kubectl describe nodes
```

#### Pod Issues
```bash
# Check pod status and events
kubectl describe pod <pod-name>

# View pod logs
kubectl logs <pod-name> -c <container-name>

# Execute into pod for debugging
kubectl exec -it <pod-name> -c <container-name> -- /bin/sh
```

#### Network Connectivity
```bash
# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default

# Test external connectivity
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl -I https://api.matillion.com

# Check service endpoints
kubectl get endpoints
```

#### Resource Issues
```bash
# Check resource usage
kubectl top nodes
kubectl top pods

# Check resource quotas
kubectl describe resourcequota

# View HPA metrics
kubectl get --raw /apis/metrics.k8s.io/v1beta1/pods
```

## Cost Optimization

### EKS Pricing Components

1. **EKS Control Plane**: $0.10/hour per cluster
2. **EC2 Worker Nodes**: Standard EC2 pricing
3. **EBS Storage**: For persistent volumes
4. **Data Transfer**: Cross-AZ and internet egress

### Optimization Strategies

#### Right-Sizing Instances
```bash
# Monitor node utilization
kubectl top nodes

# Check pod resource requests vs usage
kubectl describe pod <pod-name> | grep -A 5 "Resource"
```

#### Spot Instances for Worker Nodes
```hcl
# Configure spot instances (in module)
node_groups = {
  spot = {
    instance_types = ["m5.large", "m5.xlarge", "c5.large"]
    capacity_type  = "SPOT"
    min_size       = 1
    max_size       = 10
    desired_size   = 3
  }
}
```

#### Scheduled Scaling
```bash
# Use CronJobs for scheduled scaling
kubectl create cronjob scale-down --image=bitnami/kubectl \
  --schedule="0 18 * * *" -- kubectl scale deployment matillion-agent-app --replicas=1

kubectl create cronjob scale-up --image=bitnami/kubectl \
  --schedule="0 8 * * *" -- kubectl scale deployment matillion-agent-app --replicas=3
```

#### Resource Optimization
```yaml
# Optimize resource requests and limits
resources:
  requests:
    cpu: "500m"    # Start conservatively
    memory: "2Gi"  # Monitor actual usage
  limits:
    cpu: "2"       # Allow bursting
    memory: "4Gi"  # Prevent OOM kills
```

## Limitations and Considerations

### EKS Limitations

- **Control Plane Cost**: $0.10/hour regardless of usage
- **Node Management**: Requires EC2 instance management
- **Complexity**: Higher operational overhead than ECS Fargate
- **Learning Curve**: Requires Kubernetes knowledge

### Kubernetes Considerations

#### Pod Disruption Budgets
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: matillion-agent-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: matillion-agent
```

#### Resource Limits
```yaml
# Ensure proper resource limits to prevent noisy neighbors
resources:
  limits:
    cpu: "2"
    memory: 4Gi
    ephemeral-storage: 10Gi
```

## Migration and Upgrades

### EKS Version Upgrades

```bash
# Check current version
aws eks describe-cluster --name <cluster-name> --query cluster.version

# Upgrade control plane
aws eks update-cluster-version \
  --name <cluster-name> \
  --kubernetes-version <new-version>

# Upgrade node groups
aws eks update-nodegroup-version \
  --cluster-name <cluster-name> \
  --nodegroup-name <nodegroup-name> \
  --kubernetes-version <new-version>
```

### Migration from ECS

If migrating from ECS Fargate:

1. **Parallel Deployment**: Deploy EKS alongside existing ECS
2. **Data Migration**: Ensure data consistency during transition
3. **DNS Cutover**: Update routing to point to EKS services
4. **Monitoring**: Verify metrics and logging work correctly
5. **Cleanup**: Remove ECS resources after validation

## 🧹 Cleanup

### Remove Application
```bash
# Uninstall Helm chart
helm uninstall matillion-agent

# Remove monitoring (if installed)
helm uninstall prometheus -n monitoring
kubectl delete namespace monitoring
```

### Destroy Infrastructure
```bash
# Destroy EKS cluster and resources
terraform destroy

# Verify cleanup
aws eks list-clusters
aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/<cluster-name>,Values=owned"
```

### Manual Cleanup (if needed)
```bash
# Force delete stuck resources
kubectl delete pod <pod-name> --force --grace-period=0

# Remove finalizers from stuck namespaces
kubectl patch namespace <namespace> -p '{"metadata":{"finalizers":null}}'

# Clean up AWS Load Balancers (if any were created)
aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `<cluster-name>`)]'
```

## Support and Troubleshooting

### Common Issues

#### ImagePullBackOff
```bash
# Check image repository and credentials
kubectl describe pod <pod-name>

# Verify image exists
docker pull public.ecr.aws/matillion/etl-agent:current
```

#### OOMKilled Pods
```bash
# Check memory usage and limits
kubectl describe pod <pod-name>
kubectl top pod <pod-name>

# Increase memory limits in values file
```

#### CrashLoopBackOff
```bash
# Check application logs
kubectl logs <pod-name> -c <container-name> --previous

# Check liveness/readiness probes
kubectl describe pod <pod-name>
```

### Getting Help

1. **Kubernetes Documentation**: [kubernetes.io](https://kubernetes.io/docs/)
2. **AWS EKS Documentation**: [AWS EKS Guide](https://docs.aws.amazon.com/eks/)
3. **Helm Documentation**: [helm.sh](https://helm.sh/docs/)
4. **GitHub Issues**: Report deployment-specific problems

## Additional Resources

- [Amazon EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [Kubernetes Production Best Practices](https://kubernetes.io/docs/setup/best-practices/)
- [AWS EKS Pricing Calculator](https://calculator.aws/#/createCalculator/EKS)
- [Terraform AWS EKS Module](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest)
- [Helm Chart Development Guide](https://helm.sh/docs/chart_template_guide/)

## ⚖️ Comparison with ECS Fargate

| Feature | EKS | ECS Fargate |
|---------|-----|-------------|
| **Kubernetes Native** | Y | N |
| **Sidecar Containers** | Y | N |
| **Advanced Scaling** | Y (HPA/) | N |
| **Operational Complexity** | High | Low |
| **Cost** | Higher (control plane + nodes) | Lower (task-based) |
| **Ecosystem** | Rich (CNCF) | AWS-specific |
| **Metrics Collection** | Advanced | Basic |
| **Multi-cloud Portability** | Y | N |

Choose EKS when you need the full power of Kubernetes, advanced scaling capabilities, comprehensive metrics collection with sidecars, or plan to leverage the broader Kubernetes ecosystem.