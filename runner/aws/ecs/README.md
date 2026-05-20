# AWS ECS Deployment for Matillion Runner

This directory contains Terraform configurations for deploying the Matillion DPC Runner using AWS ECS (Elastic Container Service) with Fargate - a serverless compute engine for containers.

## Overview

AWS ECS Fargate deployment provides:
- **Serverless Containers**: No EC2 instance management required
- **Fully Managed**: AWS handles infrastructure provisioning and scaling
- **Integrated AWS Services**: Native integration with IAM, CloudWatch, VPC
- **Flexible Scaling**: Manual and automatic scaling options
- **Cost Effective**: Pay only for resources used

## Architecture

```
┌───────────────────────────────────────────┐
│              AWS Account                  │
│  ┌──────────────────────────────────────┐ │
│  │           ECS Cluster                │ │
│  │  ┌─────────────────────────────────┐ │ │
│  │  │         ECS Service             │ │ │
│  │  │  ┌────────────────────────────┐ │ │ │
│  │  │  │      Fargate Tasks         │ │ │ │
│  │  │  │  ┌───────────────────────┐ │ │ │ │
│  │  │  │  │  Matillion Runner     │ │ │ │ │
│  │  │  │  │  (Single Container)   │ │ │ │ │
│  │  │  │  └───────────────────────┘ │ │ │ │
│  │  │  └────────────────────────────┘ │ │ │
│  │  └─────────────────────────────────┘ │ │
│  └──────────────────────────────────────┘ │
│  ┌─────────────────────────────────────┐  │
│  │       AWS Secrets Manager           │  │
│  │      (OAuth Credentials)            │  │
│  └─────────────────────────────────────┘  │
│  ┌─────────────────────────────────────┐  │
│  │          S3 Bucket                  │  │
│  │       (Data Storage)                │  │
│  └─────────────────────────────────────┘  │
│  ┌─────────────────────────────────────┐  │
│  │         CloudWatch                  │  │
│  │    (Logs & Monitoring)              │  │
│  └─────────────────────────────────────┘  │
└───────────────────────────────────────────┘
```

## Prerequisites

- [Terraform 1.0+](https://www.terraform.io/downloads.html)
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate permissions
- AWS account with ECS and Fargate enabled
- VPC with subnets configured for ECS deployment

### Image Delivery & Network Requirements

The Runner image for this deployment is pulled from `public.ecr.aws/matillion/etl-agent`. Your VPC must have network access to that registry — via open egress, a whitelisted egress path, or a private mirror in your deployment region for zero-egress environments. ECR Public's API is hosted only in `us-east-1` / `us-west-2`, so deployments in other regions must reach `us-east-1` over the internet to pull the public image.

See [Network Requirements for Pulling the Runner Image](../../../blogs/runner-image-pull-network-requirements.md) for supported network patterns, the required VPC endpoints for the private-mirror pattern, and configuration steps.

### Required AWS Permissions

```bash
# Configure AWS CLI
aws configure

# Verify permissions
aws sts get-caller-identity
```

Required IAM permissions:
- ECS service management
- IAM role creation and management
- Secrets Manager access
- S3 bucket operations
- CloudWatch logs access

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd poc-agent-deployment/runner/aws/ecs
```

### 2. Configure Variables

Create or edit `terraform.tfvars`:

```hcl
# AWS Configuration
region = "us-east-1"
name   = "matillion-runner"

# Matillion Configuration
account_id         = "your-matillion-account-id"
agent_id          = "your-unique-agent-id"
matillion_region  = "us-east-1"
client_id        = "your-oauth-client-id"
client_secret    = "your-oauth-client-secret"

# Networking Configuration
vpc_id             = "vpc-12345678"
subnet_ids         = ["subnet-12345678", "subnet-87654321"]
security_group_ids = ["sg-12345678"]

# Container Configuration
image_url     = "public.ecr.aws/matillion/etl-agent:current"
desired_count = 2
runner_size   = "small"  # small | medium | large | xlarge — see Resource Sizing below
# runner_cpu / runner_memory may still be set as Fargate-valid overrides (see below)

# Optional: Ephemeral Storage
ephemeral_storage_size = 30  # GiB

# Optional: Extension Libraries
extension_library_location = ""
extension_library_protocol = ""

# Optional: S3 Bucket
create_bucket = true
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
# Check ECS service status
aws ecs describe-services --cluster <cluster-name> --services <service-name>

# View task logs
aws logs tail /aws/ecs/<cluster-name> --follow

# Check running tasks
aws ecs list-tasks --cluster <cluster-name> --service-name <service-name>
```

## ⚙️ Configuration Options

### Resource Sizing

Pick a t-shirt size with `runner_size`. Each size maps to a Fargate-valid `cpu`/`memory` pair so you don't have to remember the matrix.

| `runner_size` | vCPU | Memory | `runner_cpu` | `runner_memory` | Notes |
|---|---|---|---|---|---|
| `small` *(default)* | 1 | 4 GiB | 1024 | 4096 | Light/dev workloads, single-pipeline tenants |
| `medium` | 2 | 8 GiB | 2048 | 8192 | Most production deployments |
| `large` | 4 | 16 GiB | 4096 | 16384 | Heavy ELT, large staged datasets |
| `xlarge` | 8 | 32 GiB | 8192 | 32768 | Linux-only on Fargate |

```hcl
# Most deployments
runner_size = "medium"
desired_count = 3
ephemeral_storage_size = 50
```

#### Overrides

If you need a specific Fargate-valid combination outside the t-shirt sizes, set both `runner_cpu` and `runner_memory`. They take precedence over `runner_size`:

```hcl
runner_size   = "small"  # ignored when both overrides are set
runner_cpu    = 2048
runner_memory = 4096
```

The pair must be a valid Fargate combination — see the table in [CPU and Memory Combinations](#cpu-and-memory-combinations) below.

### Networking Configuration

#### Public Subnets
```hcl
subnet_ids = ["subnet-public-1", "subnet-public-2"]
# Ensure security groups allow outbound HTTPS (port 443)
```

#### Private Subnets (Recommended)
```hcl
subnet_ids = ["subnet-private-1", "subnet-private-2"]
# Requires NAT Gateway for internet access
```

### Security Group Requirements

```hcl
# Outbound rules required:
# - HTTPS (443) for Matillion API communication
# - Database ports (e.g., 5432 for PostgreSQL) if needed
# - DNS (53) for name resolution
```

### CPU and Memory Combinations

| CPU Units | Memory (MB) | vCPU | Use Case |
|-----------|-------------|------|----------|
| 256 | 512-2048 | 0.25 | Light workload |
| 512 | 1024-4096 | 0.5 | Development |
| 1024 | 2048-8192 | 1 | Standard production |
| 2048 | 4096-16384 | 2 | High-performance |
| 4096 | 8192-30720 | 4 | Heavy workload |

## Monitoring and Logging

### CloudWatch Integration

ECS automatically integrates with CloudWatch:

- **Container Logs**: Automatically sent to CloudWatch Logs
- **Metrics**: CPU, Memory, Network utilization
- **Service Events**: Task start/stop, health check results
- **Custom Metrics**: Application-specific metrics

### Log Groups

```bash
# View log groups
aws logs describe-log-groups --log-group-name-prefix "/aws/ecs/"

# Stream logs
aws logs tail "/aws/ecs/<service-name>" --follow
```

### CloudWatch Alarms

```bash
# CPU utilization alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "matillion-runner-high-cpu" \
  --alarm-description "High CPU utilization" \
  --metric-name CPUUtilization \
  --namespace AWS/ECS \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold
```

## Security Configuration

### IAM Roles

The deployment creates two IAM roles:

#### Task Execution Role
- Pull container images from ECR
- Write logs to CloudWatch
- Access secrets from Secrets Manager

#### Task Role
- Application-specific permissions
- S3 bucket access
- Additional AWS service permissions

### Secrets Management

```hcl
# OAuth credentials stored in AWS Secrets Manager
module "secrets_manager" {
  source = "../../../modules/aws/secrets-manager"
  
  client_id     = var.client_id
  client_secret = var.client_secret
}
```

### Network Security

#### Security Group Best Practices
```hcl
# Minimal outbound rules
resource "aws_security_group_rule" "https_outbound" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = var.security_group_id
}

# Database access (if needed)
resource "aws_security_group_rule" "database_outbound" {
  type              = "egress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/8"]
  security_group_id = var.security_group_id
}
```

## Operations

### Scaling Operations

#### Manual Scaling
```bash
# Update desired count
aws ecs update-service \
  --cluster <cluster-name> \
  --service <service-name> \
  --desired-count 5
```

#### Auto Scaling with Application Auto Scaling
```bash
# Register scalable target
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id service/<cluster-name>/<service-name> \
  --min-capacity 2 \
  --max-capacity 10
```

### Updates and Deployments

#### Application Updates
```bash
# Update task definition with new image
aws ecs update-service \
  --cluster <cluster-name> \
  --service <service-name> \
  --force-new-deployment
```

#### Rolling Updates
ECS automatically performs rolling updates:
- Stops old tasks gradually
- Starts new tasks with updated configuration
- Maintains service availability during updates

### Troubleshooting

#### Service Issues
```bash
# Check service events
aws ecs describe-services \
  --cluster <cluster-name> \
  --services <service-name> \
  --query 'services[0].events[0:5]'

# Check task definition
aws ecs describe-task-definition \
  --task-definition <task-definition-arn>
```

#### Task Startup Issues
```bash
# List tasks
aws ecs list-tasks --cluster <cluster-name>

# Describe specific task
aws ecs describe-tasks \
  --cluster <cluster-name> \
  --tasks <task-arn>

# Check task logs
aws logs get-log-events \
  --log-group-name "/aws/ecs/<service-name>" \
  --log-stream-name "<log-stream-name>"
```

#### Network Connectivity
```bash
# Test VPC connectivity
aws ec2 describe-subnets --subnet-ids subnet-12345678
aws ec2 describe-security-groups --group-ids sg-12345678

# Check NAT Gateway (for private subnets)
aws ec2 describe-nat-gateways
```

## 💰 Cost Optimization

### Pricing Model

ECS Fargate charges for:
- **vCPU**: Per second billing
- **Memory**: Per second billing
- **Storage**: Ephemeral storage above 20GB

### Optimization Strategies

#### Right-sizing
```bash
# Monitor resource usage
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=<service-name> \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Average
```

#### Spot Fargate (Limited Availability)
```hcl
# Use Spot capacity when available
capacity_provider_strategy {
  capacity_provider = "FARGATE_SPOT"
  weight           = 1
}
```

#### Scheduled Scaling
```bash
# Scale down during off-hours
aws application-autoscaling put-scheduled-action \
  --service-namespace ecs \
  --resource-id service/<cluster>/<service> \
  --scalable-dimension ecs:service:DesiredCount \
  --scheduled-action-name scale-down-evening \
  --schedule "cron(0 20 * * ? *)" \
  --scalable-target-action MinCapacity=1,MaxCapacity=1
```

## Limitations

### ECS Fargate Constraints

- **Single Container per Task**: No sidecar support
- **Limited Networking**: Basic VPC networking only
- **Storage**: Ephemeral storage only (max 200GB)
- **Task Size Limits**: Max 16 vCPU / 120 GiB on Linux Fargate (8 vCPU / 60 GiB on Windows). The `xlarge` t-shirt size is Linux-only.

### Metrics

The runner natively exposes Prometheus-compatible metrics at `/actuator/prometheus` on port 8080. For ECS deployments, consider using CloudWatch Container Insights for monitoring.

## Migration Paths

### From ECS to EKS

If you need Kubernetes-native features like HPA with custom metrics:

```bash
# Deploy EKS version
cd ../eks
terraform init
terraform apply
```

### From EC2 to Fargate

Migration considerations:
- No direct host access
- Task-based scaling instead of instance-based
- Different networking model
- Simplified IAM role structure

## Cleanup

### Destroy Infrastructure

```bash
# Destroy all resources
terraform destroy

# Verify cleanup
aws ecs list-clusters
aws secretsmanager list-secrets
aws s3 ls
```

### Manual Cleanup (if needed)

```bash
# Force delete ECS service
aws ecs update-service \
  --cluster <cluster-name> \
  --service <service-name> \
  --desired-count 0

aws ecs delete-service \
  --cluster <cluster-name> \
  --service <service-name>

# Delete CloudWatch logs
aws logs delete-log-group \
  --log-group-name "/aws/ecs/<service-name>"
```

## Performance Considerations

### Resource Allocation

Use `runner_size` (see [Resource Sizing](#resource-sizing)) to pick the cpu/memory pair. The internal map is:

```hcl
{
  small  = { cpu = 1024, memory = 4096  }   # 1 vCPU / 4 GiB
  medium = { cpu = 2048, memory = 8192  }   # 2 vCPU / 8 GiB
  large  = { cpu = 4096, memory = 16384 }   # 4 vCPU / 16 GiB
  xlarge = { cpu = 8192, memory = 32768 }   # 8 vCPU / 32 GiB
}
```

### Network Performance

- Use multiple Availability Zones for better network performance
- Consider placement constraints for data locality
- Optimize security group rules to minimize network overhead

## Support

For ECS-specific issues:

1. **AWS Status**: [AWS Service Health Dashboard](https://status.aws.amazon.com/)
2. **ECS Documentation**: [Amazon ECS Documentation](https://docs.aws.amazon.com/ecs/)
3. **AWS Support**: Create support case for platform issues
4. **GitHub Issues**: Report deployment configuration problems

## Additional Resources

- [Amazon ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [AWS Fargate Pricing](https://aws.amazon.com/fargate/pricing/)
- [ECS Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Comparison with Other Deployment Methods

| Feature | ECS Fargate | EKS | Container Apps |
|---------|-------------|-----|----------------|
| **Management** | Fully Managed | Managed Control Plane | Fully Managed |
| **Scaling** | Manual/Auto Scaling | Manual/HPA/VPA | Auto (0-300) |
| **Networking** | VPC Integration | Advanced (CNI) | Basic |
| **Sidecar Support** | N | Y | N |
| **Cost** | Task-based | Node-based | Pay-per-use |
| **AWS Integration** | Native | Native | N/A |
| **Learning Curve** | Low | High | Low |

Choose ECS Fargate for:
- AWS-native container deployment
- Simple application architectures
- Minimal operational overhead
- Strong AWS service integration
- Cost-effective serverless containers

Choose EKS for:
- Kubernetes ecosystem requirements
- Complex microservices architectures
- Multi-cloud portability
- Advanced networking and storage needs
- Sidecar container patterns (metrics)