# Prometheus Helm Chart

A modular Helm chart for deploying Prometheus monitoring components with selective deployment capabilities.

## Overview

This chart provides a flexible way to deploy Prometheus monitoring infrastructure with three main components:

- **Prometheus Server** - Core metrics storage and query engine
- **Prometheus Adapter** - Kubernetes custom metrics API adapter
- **Custom Metrics API** - Exposes custom metrics for HPA

Each component can be deployed independently, allowing integration with existing Prometheus installations.

## Features

- **Modular Deployment** - Deploy components individually or together
- **External Prometheus Support** - Connect adapter/API to existing Prometheus servers
- **Secure by Default** - Security contexts, RBAC, and network policies
- **Production Ready** - Resource limits, health checks, and monitoring

## Quick Start

### Deploy Full Stack
```bash
# Install all components (default behavior)
helm install prometheus-stack . --namespace monitoring --create-namespace
```

### Deploy Individual Components

#### Prometheus Server Only
```bash
helm install prometheus . --namespace monitoring \
  --set modules.prometheus.enabled=true \
  --set modules.adapter.enabled=false \
  --set modules.api.enabled=false
```

#### Custom Metrics API Only (with external Prometheus)
```bash
helm install metrics-api . --namespace monitoring \
  --set modules.prometheus.enabled=false \
  --set modules.adapter.enabled=true \
  --set modules.api.enabled=true \
  --set externalPrometheus.enabled=true \
  --set externalPrometheus.url="http://my-prometheus.monitoring.svc:9090"
```

## Configuration

### Global Module Control

These flags provide centralized control and **take precedence** over individual component flags.

| Parameter | Description | Default | 
|-----------|-------------|---------|
| `modules.prometheus.enabled` | Deploy Prometheus server | `true` |
| `modules.adapter.enabled` | Deploy Prometheus adapter | `true` |
| `modules.api.enabled` | Deploy custom metrics API | `true` |

### Flag Precedence Rules

The chart uses the following precedence logic:
1. **Global flags first**: `modules.*` values are checked first
2. **Legacy fallback**: If global flag is not set, falls back to individual component flags
3. **Default behavior**: If neither is set, defaults to `true` (enabled)

Example precedence resolution:
```yaml
# modules.adapter.enabled takes precedence
modules:
  adapter:
    enabled: false    # ← This wins
adapter:
  enabled: true       # ← This is ignored

# Legacy flag is used when global flag is unset
modules: {}           # No global setting
adapter:
  enabled: false      # ← This is used
```

### External Prometheus Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `externalPrometheus.enabled` | Use external Prometheus | `false` |
| `externalPrometheus.url` | External Prometheus URL | `"http://prometheus.monitoring.svc.cluster.local:9090"` |
| `externalPrometheus.namespace` | External Prometheus namespace | `"monitoring"` |
| `externalPrometheus.serviceName` | External Prometheus service name | `"prometheus"` |

### Component Configuration

#### Prometheus Server

| Parameter | Description | Default |
|-----------|-------------|---------|
| `prometheus.prometheus.image.repository` | Prometheus image | `"prom/prometheus"` |
| `prometheus.prometheus.image.tag` | Prometheus version | `"v2.22.0"` |
| `prometheus.replicas` | Number of replicas | `1` |
| `prometheus.prometheus.resources.limits.cpu` | CPU limit | `"2"` |
| `prometheus.prometheus.resources.limits.memory` | Memory limit | `"4Gi"` |

#### Prometheus Adapter

| Parameter | Description | Default |
|-----------|-------------|---------|
| `adapter.prometheusAdapter.image.repository` | Adapter image | `"gcr.io/k8s-staging-prometheus-adapter/prometheus-adapter-amd64"` |
| `adapter.prometheusAdapter.image.tag` | Adapter version | `"v0.12.0"` |
| `adapter.replicas` | Number of replicas | `1` |
| `adapter.prometheusAdapter.resources.limits.cpu` | CPU limit | `"1"` |
| `adapter.prometheusAdapter.resources.limits.memory` | Memory limit | `"2Gi"` |

#### Custom Metrics Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `adapterConfig.configYaml` | Adapter configuration | See values.yaml |
| `api.type` | Service type | `"ClusterIP"` |
| `api.ports` | Service ports | `[{"port": 443, "targetPort": 8443}]` |

## Usage Examples

### Production Configuration

```yaml
# production-values.yaml
modules:
  prometheus:
    enabled: true
  adapter:
    enabled: true
  api:
    enabled: true

prometheus:
  replicas: 2
  prometheus:
    image:
      tag: "v2.47.0"
    resources:
      limits:
        cpu: "4"
        memory: "8Gi"
      requests:
        cpu: "2"
        memory: "4Gi"

adapter:
  replicas: 2
  prometheusAdapter:
    resources:
      limits:
        cpu: "2"
        memory: "4Gi"
      requests:
        cpu: "1"
        memory: "2Gi"
```

### External Prometheus Integration

```yaml
# external-prometheus.yaml
modules:
  prometheus:
    enabled: false  # Don't deploy Prometheus server
  adapter:
    enabled: true   # Deploy adapter
  api:
    enabled: true   # Deploy custom metrics API

externalPrometheus:
  enabled: true
  url: "http://prometheus.monitoring.svc.cluster.local:9090"
  namespace: "monitoring"
  serviceName: "prometheus"

# Adapter will connect to external Prometheus at the specified URL
adapter:
  prometheusAdapter:
    resources:
      limits:
        cpu: "1"
        memory: "2Gi"
```

### Standalone Monitoring Server

```yaml
# monitoring-server.yaml
modules:
  prometheus:
    enabled: true   # Deploy Prometheus server
  adapter:
    enabled: false  # Skip adapter
  api:
    enabled: false  # Skip custom metrics API

prometheus:
  prometheus:
    resources:
      limits:
        cpu: "8"
        memory: "16Gi"
      requests:
        cpu: "4"
        memory: "8Gi"

# For large-scale monitoring without custom metrics
config:
  prometheusYml: |-
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
    scrape_configs:
      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
        - role: pod
```

## 🔧 Advanced Configuration

### Custom Metrics Rules

Configure custom metrics rules in `adapterConfig.configYaml`:

```yaml
adapterConfig:
  configYaml: |-
    rules:
      - seriesQuery: 'http_requests_per_second{namespace!="",pod!=""}'
        resources:
          overrides:
            namespace: {resource: "namespace"}
            pod: {resource: "pod"}
        name:
          matches: "^(.*)_per_second"
          as: "${1}_rate"
        metricsQuery: 'avg(<<.Series>>{<<.LabelMatchers>>})'
```

### Resource Limits and Requests

```yaml
prometheus:
  prometheus:
    resources:
      limits:
        cpu: "4"
        memory: "8Gi"
      requests:
        cpu: "2" 
        memory: "4Gi"

adapter:
  prometheusAdapter:
    resources:
      limits:
        cpu: "1"
        memory: "2Gi"
      requests:
        cpu: "500m"
        memory: "1Gi"
```

### Network Policies

```yaml
networkPolicy:
  enabled: true
  ingress:
    - from:
      - namespaceSelector:
          matchLabels:
            name: "kube-system"
    - from:
      - namespaceSelector:
          matchLabels:
            monitoring: "enabled"
```

## 🔍 Monitoring and Troubleshooting

### Check Component Status

```bash
# Check all deployed components
kubectl get pods -n monitoring -l app.kubernetes.io/instance=prometheus-stack

# Check services
kubectl get svc -n monitoring

# Check custom metrics API
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1"
```

### View Logs

```bash
# Prometheus server logs
kubectl logs -n monitoring deployment/prometheus-stack -c prometheus

# Adapter logs  
kubectl logs -n monitoring deployment/prometheus-stack-adapter

# Check metrics registration
kubectl get apiservices | grep custom.metrics
```

### Common Issues

**Adapter cannot connect to Prometheus:**
- Verify `externalPrometheus.url` is correct
- Check network connectivity between namespaces
- Ensure Prometheus is accessible from adapter pod

**Custom metrics not available:**
- Verify adapter configuration in `adapterConfig.configYaml`
- Check that metrics exist in Prometheus
- Ensure proper RBAC permissions

**High resource usage:**
- Adjust resource limits in values file
- Consider reducing scrape intervals
- Monitor Prometheus storage usage

## Migration Guide

### From Full Stack to External Prometheus

1. **Deploy external Prometheus connection:**
```bash
helm upgrade prometheus-stack . \
  --set modules.prometheus.enabled=false \
  --set externalPrometheus.enabled=true \
  --set externalPrometheus.url="http://my-prometheus.monitoring.svc:9090"
```

2. **Verify adapter connectivity:**
```bash
kubectl logs -n monitoring deployment/prometheus-stack-adapter
```

3. **Test custom metrics:**
```bash
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1"
```

### Upgrading Components

```bash
# Upgrade with new values
helm upgrade prometheus-stack . -f new-values.yaml

# Check rollout status
kubectl rollout status -n monitoring deployment/prometheus-stack
kubectl rollout status -n monitoring deployment/prometheus-stack-adapter
```

## Requirements

- Kubernetes 1.19+
- Helm 3.0+
- RBAC enabled cluster
