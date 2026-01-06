# Matillion Agent Helm Charts

This directory contains Helm charts for deploying the Matillion Data Productivity Cloud (DPC) Agent on Kubernetes with comprehensive monitoring capabilities.

## Charts

### `agent/` - Matillion DPC Agent
The main Helm chart that deploys the Matillion Agent with a metrics exporter sidecar.

### `prometheus/` - Modular Prometheus Stack  
Supporting chart for Prometheus metrics collection, custom metrics API, and Prometheus adapter with selective deployment capabilities. Supports integration with external Prometheus servers.

## Quick Start

### Prerequisites

#### Namespaces
Create the required namespaces before installation:

```bash
# Create namespace for Matillion Agent
kubectl create namespace matillion

# Create namespace for Prometheus monitoring
kubectl create namespace prometheus
```

### Install Agent Chart

> **Security Best Practice**: Always use values files instead of `--set` flags for sensitive data like secrets, API keys, and credentials. Command-line arguments may be visible in process lists and shell history.

#### Option 1: AWS EKS with IAM Roles (Recommended)
```bash
# Use the AWS template with environment variables
cp test-values.yaml my-eks-values.yaml
# Set your environment variables and customize the file
export MATILLION_AGENT_CLIENT_ID="your-client-id"
export MATILLION_AGENT_CLIENT_SECRET="your-client-secret"
export MATILLION_AGENT_ROLE_ARN="arn:aws:iam::123456789012:role/your-role"
export MATILLION_AGENT_ACCOUNT_ID="your-account-id"
export MATILLION_AGENT_AGENT_ID="your-agent-id"

# Install with values file
envsubst < my-eks-values.yaml | helm install matillion-agent ./agent \
  --namespace matillion \
  -f -
```

#### Option 2: Local/Minikube with Direct AWS Credentials
```bash
# Create a local AWS credentials values file
cp values.yaml my-local-values.yaml
# Edit my-local-values.yaml to enable aws.local and add your credentials

# Install with values file
helm install matillion-agent ./agent \
  --namespace matillion \
  -f my-local-values.yaml
```


### Recommended Values File Approach

#### Step 1: Choose the Right Template
```bash
# For AWS EKS with environment variables (recommended)
cp test-values.yaml production-values.yaml

# For AWS with direct values or local development
cp values.yaml development-values.yaml

# For Azure deployment (example configuration)
cp local.yaml azure-values.yaml
```

#### Step 2: Customize Your Values
```bash
# Edit your chosen values file
vim production-values.yaml  # or development-values.yaml

# For files with environment variables, set them first
export MATILLION_AGENT_CLIENT_ID="your-client-id"
export MATILLION_AGENT_CLIENT_SECRET="your-client-secret"
# ... other variables

# Validate the template before installation
helm template matillion-agent ./agent \
  --namespace matillion \
  -f production-values.yaml \
  --validate
```

#### Step 3: Install with Values File
```bash
# Install using your customized values file
helm install matillion-agent ./agent \
  --namespace matillion \
  -f production-values.yaml

# For files with environment variables
envsubst < production-values.yaml | helm install matillion-agent ./agent \
  --namespace matillion \
  -f -

# For multiple values files (e.g., base + overrides)
helm install matillion-agent ./agent \
  --namespace matillion \
  -f values.yaml \
  -f my-overrides.yaml
```

### Install Prometheus Monitoring

#### Full Stack Deployment (Default)
```bash
# Install complete Prometheus stack (Prometheus server + adapter + custom metrics API)
helm install prometheus ./prometheus --namespace prometheus

# Verify all components are running
kubectl get pods -n prometheus
```

#### Selective Module Deployment
```bash
# Deploy only Prometheus adapter (connect to external Prometheus)
helm install prometheus ./prometheus --namespace prometheus \
  --set modules.prometheus.enabled=false \
  --set modules.adapter.enabled=true \
  --set modules.api.enabled=false \
  --set externalPrometheus.enabled=true \
  --set externalPrometheus.url="http://my-prometheus.monitoring.svc:9090"

# Deploy only custom metrics API
helm install prometheus ./prometheus --namespace prometheus \
  --set modules.prometheus.enabled=false \
  --set modules.adapter.enabled=true \
  --set modules.api.enabled=true \
  --set externalPrometheus.enabled=true \
  --set externalPrometheus.url="http://my-prometheus.monitoring.svc:9090"

# Deploy only Prometheus server
helm install prometheus ./prometheus --namespace prometheus \
  --set modules.prometheus.enabled=true \
  --set modules.adapter.enabled=false \
  --set modules.api.enabled=false
```

## Configuration

### Required Values

| Parameter | Description | Example |
|-----------|-------------|---------|
| `dpcAgent.dpcAgent.env.accountId` | Your Matillion account ID | `"12345"` |
| `dpcAgent.dpcAgent.env.agentId` | Unique agent identifier | `"agent-prod-01"` |
| `dpcAgent.dpcAgent.env.matillionRegion` | Matillion region | `"us-east-1"` |
| `config.oauthClientId` | OAuth client ID | `"client-123"` |
| `config.oauthClientSecret` | OAuth client secret | `"secret-456"` |
| `serviceAccount.roleArn` | AWS IAM role ARN (required for EKS) | `"arn:aws:iam::..."` |
| `aws.local.enabled` | Enable direct AWS credentials | `false` |
| `aws.local.region` | AWS Region (when local enabled) | `"us-west-2"` |
| `aws.local.accessKeyId` | AWS Access Key ID (when local enabled) | `"AKIA..."` |
| `aws.local.secretAccessKey` | AWS Secret Access Key (when local enabled) | `"secret..."` |

### Optional Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `dpcAgent.replicas` | Number of agent replicas | `2` |
| `dpcAgent.dpcAgent.resources.limits.cpu` | CPU limit for agent | `"2"` |
| `dpcAgent.dpcAgent.resources.limits.memory` | Memory limit for agent | `4Gi` |
| `dpcAgent.metricsExporter.resources.limits.cpu` | CPU limit for sidecar | `"100m"` |
| `dpcAgent.metricsExporter.resources.limits.memory` | Memory limit for sidecar | `128Mi` |

### Metrics Sidecar Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `dpcAgent.metricsExporter.image.repository` | Metrics exporter image | `"brbajematillion/metrics-sidecar"` |
| `dpcAgent.metricsExporter.image.tag` | Image tag | `"latest"` |
| `dpcAgent.metricsExporter.imagePullPolicy` | Pull policy | `"Always"` |

## Prometheus Chart Configuration

### Module Control Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `modules.prometheus.enabled` | Deploy Prometheus server | `true` |
| `modules.adapter.enabled` | Deploy Prometheus adapter | `true` |
| `modules.api.enabled` | Deploy custom metrics API | `true` |

### External Prometheus Integration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `externalPrometheus.enabled` | Use external Prometheus server | `false` |
| `externalPrometheus.url` | External Prometheus URL | `"http://prometheus.monitoring.svc.cluster.local:9090"` |
| `externalPrometheus.namespace` | External Prometheus namespace | `"monitoring"` |
| `externalPrometheus.serviceName` | External Prometheus service name | `"prometheus"` |

### Individual Component Control

| Parameter | Description | Default |
|-----------|-------------|---------|
| `adapter.enabled` | Enable adapter deployment (legacy) | `true` |
| `api.enabled` | Enable API deployment (legacy) | `true` |
| `prometheus.enabled` | Enable Prometheus deployment (legacy) | `true` |

### Horizontal Pod Autoscaler

| Parameter | Description | Default |
|-----------|-------------|---------|
| `hpa.maxReplicas` | Maximum replicas | `10` |
| `hpa.minReplicas` | Minimum replicas | `2` |
| `hpa.metrics.target.averageValue` | Target metric value | `"50"` |

## Monitoring

### Prometheus Metrics

The deployment automatically includes a metrics exporter sidecar that provides:

- `app_version_info` - Build version information
- `app_agent_status` - Agent running status (1=running, 0=stopped)
- `app_active_task_count` - Number of active tasks
- `app_active_request_count` - Number of active requests  
- `app_open_sessions_count` - Number of open sessions

### Service Discovery

Prometheus can automatically discover metrics endpoints using annotations:

```yaml
prometheus.io/scrape: "true"
prometheus.io/port: "8000"
prometheus.io/path: "/metrics"
```

## Advanced Configuration

### Custom Image Repositories

```yaml
dpcAgent:
  dpcAgent:
    image:
      repository: "your-registry/matillion-agent"
      tag: "v1.2.3"
  metricsExporter:
    image:
      repository: "your-registry/metrics-exporter"
      tag: "v1.0.0"
```

### Resource Limits

```yaml
dpcAgent:
  dpcAgent:
    resources:
      limits:
        cpu: "4"
        memory: 8Gi
      requests:
        cpu: "2"
        memory: 4Gi
  metricsExporter:
    resources:
      limits:
        cpu: "200m"
        memory: 256Mi
      requests:
        cpu: "100m"
        memory: 128Mi
```

### Cloud Provider Specific

#### AWS EKS with IAM Roles
```yaml
cloudProvider: "aws"
serviceAccount:
  roleArn: "arn:aws:iam::123456789012:role/matillion-agent"
```

#### AWS Local/Minikube with Direct Credentials
```yaml
cloudProvider: "aws"
aws:
  local:
    enabled: true
    region: "us-west-2"
    accessKeyId: "AKIAEXAMPLE123"
    secretAccessKey: "your-secret-access-key"
# Note: serviceAccount.roleArn is not needed when using local credentials
```

#### Azure AKS with Workload Identity
```yaml
cloudProvider: "azure" 
serviceAccount:
  clientId: "your-workload-identity-client-id"
```

#### Azure AKS with Service Principal
```yaml
cloudProvider: "azure"
azure:
  servicePrincipal:
    enabled: true
    clientId: "your-service-principal-client-id"
    clientSecret: "your-service-principal-secret"
    tenantId: "your-azure-tenant-id"
```

## Testing

### Template Validation
```bash
# Test template rendering with values file
helm template test-release ./agent \
  --namespace matillion \
  -f test-values.yaml

# Validate against Kubernetes API
helm template test-release ./agent \
  --namespace matillion \
  -f test-values.yaml | \
  kubectl apply --dry-run=client -f -

# Use helm's built-in validation
helm install matillion-agent ./agent \
  --namespace matillion \
  -f test-values.yaml \
  --dry-run --validate
```

### Chart Testing
```bash
# Install chart-testing tool
helm plugin install https://github.com/helm/chart-testing

# Test charts
ct install --charts ./agent
```

## Upgrades

### Version Upgrades
```bash
# Upgrade chart to new version
helm upgrade matillion-agent ./agent \
  --namespace matillion \
  -f my-values.yaml

# Upgrade with new image version (update in values file)
# Edit my-values.yaml to change image.tag: "v2.1.1"
helm upgrade matillion-agent ./agent \
  --namespace matillion \
  -f my-values.yaml

# Check upgrade status
helm status matillion-agent
```

### Rollback
```bash
# Rollback to previous version
helm rollback matillion-agent 1
```

## Troubleshooting

### Common Issues

**Agent pod not starting:**
```bash
# Check pod status
kubectl get pods -n matillion -l app=matillion-agent

# Check pod logs
kubectl logs -n matillion -l app=matillion-agent -c matillion-agent

# Check events
kubectl describe pod -n matillion -l app=matillion-agent
```

**Metrics not being scraped:**
```bash
# Check sidecar logs
kubectl logs -n matillion -l app=matillion-agent -c metrics-exporter

# Test metrics endpoint
kubectl port-forward -n matillion deployment/matillion-agent 8000:8000
curl http://localhost:8000/metrics

# Check Prometheus is discovering targets
kubectl port-forward -n prometheus svc/prometheus 9090:9090
# Navigate to http://localhost:9090/targets
```

### Debug Mode

Enable debug logging:
```yaml
dpcAgent:
  dpcAgent:
    env:
      LOG_LEVEL: "DEBUG"
```

## Examples

### Production EKS Configuration
```yaml
# production-values.yaml
cloudProvider: "aws"
config:
  oauthClientId: "your-client-id"
  oauthClientSecret: "your-client-secret"  # Consider using external secrets
serviceAccount:
  roleArn: "arn:aws:iam::123456789012:role/matillion-agent-prod"
dpcAgent:
  replicas: 3
  dpcAgent:
    env:
      accountId: "12345"
      agentId: "prod-agent-01"
      matillionRegion: "us-east-1"
    image:
      repository: "your-registry/matillion-agent"
      tag: "v2.1.0"
      imagePullPolicy: "IfNotPresent"
    resources:
      limits:
        cpu: "2"
        memory: 4Gi
      requests:
        cpu: "1"
        memory: 2Gi
  metricsExporter:
    image:
      repository: "your-registry/metrics-exporter"
      tag: "v1.0.0"
      imagePullPolicy: "IfNotPresent"
hpa:
  maxReplicas: 20
  minReplicas: 3
  metrics:
    target:
      averageValue: "60"
networkPolicy:
  enabled: true
  additionalEgressRules:
    - to:
      - namespaceSelector:
          matchLabels:
            name: prometheus
      ports:
      - protocol: TCP
        port: 9090
```

### Development Configuration
```yaml
# dev-values.yaml
dpcAgent:
  replicas: 1
  dpcAgent:
    resources:
      limits:
        cpu: "1"
        memory: 2Gi
  metricsExporter:
    image:
      tag: "latest"
      imagePullPolicy: "Always"
hpa:
  maxReplicas: 3
  minReplicas: 1
```

### Local/Minikube Configuration
```yaml
# minikube-values.yaml (based on values.yaml template)
cloudProvider: "aws"
config:
  oauthClientId: "dev-client-id"
  oauthClientSecret: "dev-client-secret"
aws:
  local:
    enabled: true
    region: "us-west-2"
    accessKeyId: "AKIAEXAMPLE123"  # Use environment variables in practice
    secretAccessKey: "your-secret-key"  # Use environment variables in practice
dpcAgent:
  replicas: 1
  dpcAgent:
    env:
      accountId: "54321"
      agentId: "minikube-dev-agent"
      matillionRegion: "us-east-1"
    image:
      repository: "matillion-agent"
      tag: "latest"
      imagePullPolicy: "Always"
    resources:
      limits:
        cpu: "500m"
        memory: 1Gi
      requests:
        cpu: "250m"
        memory: 512Mi
  metricsExporter:
    image:
      repository: "metrics-exporter"
      tag: "latest"
    resources:
      limits:
        cpu: "100m"
        memory: 128Mi
      requests:
        cpu: "50m"
        memory: 64Mi
hpa:
  maxReplicas: 2
  minReplicas: 1
  metrics:
    target:
      averageValue: "70"
networkPolicy:
  enabled: false  # Simplified for local development
```

### Prometheus Modular Deployment Examples

#### External Prometheus Integration
```yaml
# external-prometheus-values.yaml
# Deploy only adapter and API to connect to existing Prometheus
modules:
  prometheus:
    enabled: false
  adapter:
    enabled: true
  api:
    enabled: true

externalPrometheus:
  enabled: true
  url: "http://prometheus.monitoring.svc.cluster.local:9090"
  namespace: "monitoring"
  serviceName: "prometheus"

# Install command:
# helm install prometheus ./prometheus --namespace prometheus -f external-prometheus-values.yaml
```

#### Standalone Prometheus Server
```yaml
# prometheus-only-values.yaml  
# Deploy only Prometheus server without adapter/API
modules:
  prometheus:
    enabled: true
  adapter:
    enabled: false
  api:
    enabled: false

prometheus:
  prometheus:
    resources:
      limits:
        cpu: "4"
        memory: 8Gi
      requests:
        cpu: "1"
        memory: 2Gi

# Install command:
# helm install prometheus ./prometheus --namespace prometheus -f prometheus-only-values.yaml
```

#### Custom Metrics Only
```yaml
# custom-metrics-values.yaml
# Deploy only custom metrics components (adapter + API)
modules:
  prometheus:
    enabled: false
  adapter:
    enabled: true
  api:
    enabled: true

externalPrometheus:
  enabled: true
  url: "http://my-prometheus.production.svc:9090"

# Install command:
# helm install prometheus ./prometheus --namespace prometheus -f custom-metrics-values.yaml
```

### Secrets Management Example
```yaml
# secrets-values.yaml (keep this file secure and out of version control)
config:
  oauthClientId: "actual-client-id"
  oauthClientSecret: "actual-client-secret"
aws:
  local:
    accessKeyId: "AKIAACTUALKEY123"
    secretAccessKey: "actual-secret-access-key"
```

```bash
# .gitignore
secrets-values.yaml
*-secrets.yaml
my-*-values.yaml
```

## Local Development with Minikube

### Setup Minikube
```bash
# Start minikube
minikube start --cpus=4 --memory=8g

# Enable ingress addon
minikube addons enable ingress
```

### Deploy to Minikube
```bash
# Create namespaces
kubectl create namespace matillion
kubectl create namespace prometheus

# Deploy Prometheus first
helm install prometheus ./prometheus --namespace prometheus

# Deploy agent with values file (recommended)
cp values.yaml minikube-values.yaml
# Edit minikube-values.yaml to enable aws.local and add your credentials

helm install matillion-agent ./agent \
  --namespace matillion \
  -f minikube-values.yaml


# Check deployment status
kubectl get pods -n matillion
kubectl get pods -n prometheus
```