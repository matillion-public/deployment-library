# AWS Deployments for Matillion Agent

This directory contains Terraform configurations for deploying the Matillion DPC Agent on AWS using two different container orchestration platforms.

## Deployment Options

### [ECS Fargate](./ecs/)
Serverless container deployment using AWS ECS with Fargate.

**Best for:**
- Serverless container workloads
- Simple architectures
- Minimal operational overhead
- AWS-native integration
- Cost-effective container hosting

**Key Features:**
- No infrastructure management required
- Pay-per-use pricing model
- Automatic scaling capabilities
- Native AWS service integration
- CloudWatch monitoring included

### [EKS](./eks/)
Managed Kubernetes service deployment using Amazon EKS.

**Best for:**
- Kubernetes ecosystem requirements
- Complex microservices architectures
- Advanced networking needs
- Sidecar container patterns
- Multi-cloud portability

**Key Features:**
- Full Kubernetes API compatibility
- Advanced scaling (HPA/VPA)
- Comprehensive networking (CNI)
- Sidecar container support
- Extensive ecosystem tooling

## Quick Comparison

| Feature | ECS Fargate | EKS |
|---------|-------------|-----|
| **Management Overhead** | Minimal | Moderate |
| **Learning Curve** | Low | High |
| **Scaling Options** | Manual/Auto Scaling | HPA/VPA/Cluster Autoscaler |
| **Networking** | VPC Integration | Advanced CNI |
| **Sidecar Support** | N | Y |
| **Cost Model** | Task-based | Node-based |
| **AWS Integration** | Native | Native |
| **Metrics Collection** | CloudWatch only | Sidecar + CloudWatch |

## Choosing the Right Option

### Choose ECS Fargate when:
- You want minimal operational complexity
- Your application has a simple architecture
- You prefer AWS-managed infrastructure
- Cost optimization through serverless pricing is important
- You don't need advanced Kubernetes features

### Choose EKS when:
- You need advanced Kubernetes features
- Your architecture requires sidecar containers
- You want comprehensive metrics collection
- You need advanced networking capabilities
- You plan to use Kubernetes ecosystem tools

## Common Prerequisites

Both deployment options require:

- [Terraform 1.0+](https://www.terraform.io/downloads.html)
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate permissions
- Valid AWS account with required service quotas
- Matillion account credentials (OAuth client ID/secret)

### AWS Permissions Required

Both deployments need IAM permissions for:
- VPC and networking resources
- IAM role creation and management
- AWS Secrets Manager access
- S3 bucket operations
- CloudWatch logs and monitoring

**ECS Additional Permissions:**
- ECS service and task management
- ECR repository access

**EKS Additional Permissions:**
- EKS cluster management
- EC2 instance management (for worker nodes)
- Auto Scaling group management

## Getting Started

### 1. Choose Your Deployment Method

Navigate to the appropriate subdirectory:

```bash
# For ECS Fargate deployment
cd aws/ecs/

# For EKS deployment  
cd aws/eks/
```

### 2. Follow Platform-Specific Instructions

Each deployment option has detailed README files with:
- Platform-specific prerequisites
- Configuration options
- Deployment commands
- Monitoring and troubleshooting guides
- Operational procedures

## Security Considerations

Both deployments implement security best practices:

### Secrets Management
- OAuth credentials stored in AWS Secrets Manager
- No secrets in Terraform state or configuration files
- IAM-based access control to secrets

### Network Security
- VPC isolation with private subnets (recommended)
- Security groups with minimal required access
- HTTPS-only communication with Matillion services

### IAM Security
- Principle of least privilege for service roles
- Separate execution and task roles
- No long-term access keys required

## Monitoring & Observability

### CloudWatch Integration
Both platforms provide:
- Container logs automatically sent to CloudWatch
- CPU, memory, and network metrics
- Custom application metrics support
- CloudWatch alarms for alerting

### Platform-Specific Monitoring

**ECS Fargate:**
- Service-level metrics
- Task health monitoring
- Container Insights (optional)

**EKS:**
- Node-level metrics
- Pod and service metrics
- Kubernetes events
- Support for Prometheus/Grafana

## Cost Considerations

### ECS Fargate Pricing
- Pay for actual vCPU and memory usage
- Per-second billing
- No infrastructure overhead
- Additional charges for storage above 20GB

### EKS Pricing
- EKS control plane: $0.10/hour per cluster
- EC2 instances for worker nodes
- Data transfer charges
- Additional storage costs

### Cost Optimization Tips
- Right-size resource allocations based on monitoring data
- Use Spot instances where appropriate (EKS)
- Implement auto-scaling to match demand
- Schedule scaling for predictable workload patterns

## Migration Between Platforms

### ECS to EKS Migration
If you need to migrate from ECS to EKS:

1. Deploy EKS infrastructure in parallel
2. Test application functionality on EKS
3. Update DNS/load balancer routing
4. Decommission ECS resources

### EKS to ECS Migration
If you need to simplify from EKS to ECS:

1. Verify no Kubernetes-specific features are required
2. Deploy ECS infrastructure in parallel
3. Migrate application configuration
4. Update routing and decommission EKS

## Cleanup

To remove either deployment:

```bash
# Navigate to the deployed platform directory
cd aws/ecs/  # or aws/eks/

# Destroy all resources
terraform destroy

# Confirm cleanup
aws ecs list-clusters  # for ECS
aws eks list-clusters   # for EKS
```

## Support & Troubleshooting

### Platform-Specific Support
- **ECS Issues**: See [ECS README](./ecs/README.md) troubleshooting section
- **EKS Issues**: See [EKS README](./eks/README.md) troubleshooting section

### Common Issues
- **IAM Permissions**: Ensure AWS CLI has required permissions
- **VPC Configuration**: Verify subnets and security groups
- **Secrets Access**: Check Secrets Manager permissions
- **Resource Limits**: Verify AWS service quotas

### Getting Help
1. Check platform-specific README files
2. Review AWS service documentation
3. Check Terraform AWS provider documentation
4. Create GitHub issues for deployment problems

## Additional Resources

- [AWS ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [AWS Container Services Comparison](https://aws.amazon.com/containers/)