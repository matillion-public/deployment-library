# Matillion Runner Deployment Blog Series

Welcome to the comprehensive blog series covering the Matillion Runner Deployment repository. These articles provide in-depth insights into deploying, scaling, monitoring, and securing Matillion Data Productivity Cloud (DPC) runners in production environments.

## Blog Articles

### 1. [Why Use the Matillion Runner Deployment Repository?](./why-use-matillion-agent-deployment.md)
**Essential reading for decision makers and architects**

Discover why this repository is the ideal solution for production Matillion runner deployments. Learn about:
- Multi-cloud flexibility and vendor lock-in avoidance
- Built-in observability and monitoring capabilities
- Security-first architecture principles
- Infrastructure as Code benefits
- Real-world use cases and business benefits

**Target Audience:** DevOps managers, Cloud architects, Data platform engineers

---

### 2. [How to Deploy the Matillion Runner: Complete Guide](./how-to-deploy-matillion-agent.md)
**Step-by-step deployment instructions for all platforms**

Comprehensive deployment guide covering all five supported methods:
- **Kubernetes with Helm Charts** (recommended approach)
- **AWS ECS with Terraform** (serverless container deployment)
- **Azure AKS with Terraform** (managed Kubernetes with Azure integration)
- **AWS EKS with Terraform** (managed Kubernetes with AWS integration)
- **Azure Container Instances (ACI) with Terraform** (serverless container deployment)

Includes configuration examples, troubleshooting tips, and best practices for each platform.

**Target Audience:** DevOps engineers, Cloud platform engineers, Deployment specialists

---

### 3. [Autoscaling Matillion Runners: Smart Scaling for Data Workloads](./autoscaling-matillion-agents.md)
**Advanced scaling strategies for data processing workloads**

Go beyond basic CPU/memory scaling with intelligent, application-aware autoscaling:
- Custom metrics-based scaling (`app_active_task_count`, `app_active_request_count`)
- Kubernetes HPA with sophisticated behavior policies
- AWS ECS and Azure AKS scaling strategies
- Production vs. development scaling profiles
- Cost optimization through smart scaling

**Target Audience:** Cloud Platform engineers, SREs, Performance optimization specialists

---

### 4. [Monitoring and Observability for Matillion Runners](./monitoring-and-observability.md)
**Comprehensive visibility into your data processing infrastructure**

Transform your runner deployment from a black box into a transparent, manageable system:
- Custom metrics sidecar with Prometheus integration
- Grafana dashboards for data pipeline insights
- Intelligent alerting for proactive issue detection
- Log aggregation and analysis strategies
- Multi-cloud monitoring approaches

**Target Audience:** SREs, monitoring specialists, operations teams

---

### 5. [Network Requirements for Pulling the Runner Image](./runner-image-pull-network-requirements.md)
**Network access requirements for pulling the Runner image in restricted environments**

Operational reference for cloud engineers and solution architects deploying the Matillion Runner in environments with restricted network egress:
- Where the Runner image lives (AWS ECR Public, Matillion-operated public ACR)
- Decision tree for open egress, whitelisted egress, and zero-egress postures
- AWS private mirror pattern with VPC endpoints
- Azure private mirror pattern with Private Endpoints and ACR Artifact Cache
- Symptoms reference for ECS Fargate, EKS, Container Apps, and AKS image pull failures

**Target Audience:** Cloud engineers, solution architects, DevOps engineers deploying into regulated or restricted networks

---

### 6. [Right-sizing Matillion Agents: T-Shirt Sizing Across Orchestrators](./right-sizing-matillion-agents.md)
**Pick the right CPU/memory for your agent on any cloud, without re-reading every orchestrator's matrix**

A practical guide to the new `runner_size` / `runnerSize` variable that replaces hand-rolled `cpu`/`memory` values across every deployment template:
- The four t-shirt sizes (small / medium / large / xlarge) and what each one costs
- Per-orchestrator constraints — Fargate's valid combinations, Container Apps' workload-profile gotcha, Kubernetes node-headroom rules
- When to override the size map and what's safe to set
- A repeatable approach for picking the right size from existing telemetry

**Target Audience:** Cloud engineers, platform leads, anyone deploying agents into a new environment

---

## Choosing the Right Article

### New to the Repository?
Start with **"Why Use the Matillion Runner Deployment Repository?"** to understand the value proposition and use cases.

### Ready to Deploy?
Jump to **"How to Deploy the Matillion Runner"** for step-by-step deployment instructions for your chosen platform.

### Optimizing Performance?
Read **"Autoscaling Matillion Runners"** to implement intelligent scaling based on actual workload metrics.

### Need Better Visibility?
Explore **"Monitoring and Observability"** for comprehensive monitoring strategies and dashboard examples.

### Deploying into a Restricted Network?
Read **"Network Requirements for Pulling the Runner Image"** to understand image delivery and network access requirements, including private-mirror patterns for zero-egress environments.

### Picking the Right Resources?
Read **"Right-sizing Matillion Agents"** before your first deploy or when you suspect throttling/OOMs. Covers the small/medium/large/xlarge sizes, per-orchestrator constraints, and how to validate the choice from telemetry.

### Security-Focused?
Review **"Security Best Practices"** for defense-in-depth security implementation.

## Prerequisites for Using These Guides

### Common Requirements
- Basic understanding of containerization and orchestration
- Familiarity with your chosen cloud platform (AWS, Azure, or Kubernetes)
- Access to Matillion DPC account credentials

### Platform-Specific Prerequisites
- **Kubernetes**: Helm 3.x, kubectl, cluster access
- **AWS ECS**: Terraform, AWS CLI, appropriate IAM permissions
- **AWS EKS**: Terraform, AWS CLI, kubectl, appropriate IAM permissions
- **Azure AKS**: Terraform, Azure CLI, kubectl, subscription access
- **Azure ACI**: Terraform, Azure CLI, subscription access

## Additional Resources

### Repository Documentation
- [Main README](../README.md) - Repository overview and quick start
- [Helm Chart Documentation](../runner/helm/README.md) - Kubernetes-specific details
- [AWS ECS Documentation](../runner/aws/ecs/README.md) - AWS deployment specifics
- [Azure AKS Documentation](../modules/azure/aks/readme.md) - Azure deployment details

### External References
- [Matillion Documentation](https://docs.matillion.com/) - Official product documentation
- [Kubernetes Documentation](https://kubernetes.io/docs/) - Kubernetes reference
- [AWS ECS Documentation](https://docs.aws.amazon.com/ecs/) - Amazon ECS service guide
- [Azure AKS Documentation](https://docs.microsoft.com/en-us/azure/aks/) - Azure Kubernetes Service

## Quick Reference

### Common Configuration Values
```yaml
# Essential configuration for all deployments
account_id: "YOUR_MATILLION_ACCOUNT_ID"
agent_id: "YOUR_AGENT_ID"   # API contract field — keep "agent" naming
matillion_region: "us-east-1"  # or your preferred region

# Resource sizing — one variable, every orchestrator
# small  = 1 vCPU / 4 GiB    (default; light/dev workloads)
# medium = 2 vCPU / 8 GiB    (recommended for most production)
# large  = 4 vCPU / 16 GiB   (heavy ELT, large staged datasets)
# xlarge = 8 vCPU / 32 GiB   (Linux-only on ECS Fargate)
# Helm charts use `runnerSize`; ECS/Container Apps Terraform use `runner_size`.
# See ./right-sizing-matillion-agents.md for the full per-orchestrator picture.
runner_size: "small"

# Scaling defaults
min_replicas: 2
max_replicas: 10
app_active_task_count: 18
app_active_request_count: 18
```

### Essential Commands
```bash
# Kubernetes deployment
helm install matillion-runner runner/helm/runner/ -f custom-values.yaml

# AWS ECS deployment
cd runner/aws/ecs && terraform init && terraform apply

# AWS EKS deployment
cd runner/aws/eks && terraform init && terraform apply

# Azure AKS deployment
cd runner/azure/aks && terraform init && terraform apply

# Azure ACI deployment
cd runner/azure/aci && terraform init && terraform apply

# Check deployment status
kubectl get pods -l app.kubernetes.io/name=matillion-runner
aws ecs describe-services --cluster matillion-runner-cluster
aws eks describe-cluster --name matillion-runner-eks
az aks show --resource-group matillion-rg --name matillion-aks
az container show --resource-group matillion-rg --name matillion-runner-aci
```

## Contributing to the Blog Series

Found errors, have suggestions, or want to contribute additional content? Please:

1. Open an issue in the repository for discussion
2. Submit a pull request with improvements
3. Share your real-world experiences and use cases

## Support and Community

- **GitHub Issues**: [Repository Issues](../../issues) - Bug reports and feature requests
- **Documentation**: Comprehensive guides in each article
- **Best Practices**: Real-world examples and production-tested configurations

---

*These blog articles represent production-tested configurations and best practices from deploying Matillion runners in enterprise environments. They are maintained alongside the repository code to ensure accuracy and relevance.*
