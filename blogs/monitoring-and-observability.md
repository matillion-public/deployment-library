# Monitoring and Observability for Matillion Agents

In production data environments, visibility into your agent performance isn't optional—it's critical. Data pipelines that fail silently, agents that degrade performance without warning, and resource bottlenecks that emerge unexpectedly can bring entire data operations to a halt. The Matillion Agent Deployment repository includes comprehensive monitoring and observability features designed specifically for data processing workloads.

## Why Standard Monitoring Falls Short for Data Agents

Traditional infrastructure monitoring focuses on generic metrics like CPU, memory, and disk usage. For data processing agents, these metrics tell only part of the story:

- **High CPU doesn't mean high productivity** (could be inefficient queries)
- **Memory spikes might be normal** for large dataset processing
- **Network I/O patterns** are different for data transfer vs. processing
- **Error rates** don't capture data quality issues or pipeline failures

Data agents need **application-aware monitoring** that tracks business-relevant metrics alongside infrastructure health.

## Built-in Metrics Sidecar: Your Data Pipeline Observatory

### Custom Metrics That Matter

The repository includes a **custom metrics exporter sidecar** that exposes Prometheus-compatible metrics specifically designed for data processing agents:

```python
# Key metrics exposed by the sidecar
{
    "agent_status": 1,                    # 1 = running, 0 = stopped
    "active_task_count": 15,              # Currently executing data tasks
    "active_request_count": 8,            # Active API requests
    "open_sessions": 12,                  # Database connections
    "build_info": {
        "version": "2.1.0",
        "commit": "abc123",
        "build_timestamp": "2024-01-15T10:30:00Z"
    }
}
```

### Real-World Monitoring Scenarios

#### Scenario 1: Peak Load Detection
```promql
# Alert when agents are processing too many concurrent tasks
app_active_task_count > 18

# Track task completion rates
rate(app_completed_tasks_total[5m])

# Identify agents approaching capacity
app_active_task_count / app_max_task_capacity > 0.8
```

#### Scenario 2: Connection Pool Monitoring
```promql
# Monitor database connection health
app_open_sessions > 100

# Detect connection leaks
increase(app_open_sessions[30m]) > 0 and app_active_task_count == 0

# Track connection utilization
app_open_sessions / app_max_connections * 100
```

#### Scenario 3: Performance Degradation Detection
```promql
# Average task execution time increasing
avg_over_time(app_task_duration_seconds[1h]) > 300

# Request response time degradation
histogram_quantile(0.95, app_request_duration_seconds_bucket) > 30
```

## Prometheus Integration: Enterprise-Grade Metrics Collection

### Automatic Service Discovery

The Kubernetes deployment includes automatic Prometheus discovery through annotations:

```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8000"
    prometheus.io/path: "/metrics"
    prometheus.io/interval: "15s"
```

### Complete Prometheus Configuration

```yaml
# Prometheus scrape configuration
scrape_configs:
  - job_name: 'matillion-agents'
    kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
          - default
          - matillion
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__
```

### Metrics Retention and Storage

```yaml
# Prometheus configuration for data agent metrics
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'production'
    environment: 'prod'

rule_files:
  - "matillion_agent_rules.yml"

storage:
  tsdb:
    retention.time: 30d      # 30 days for detailed metrics
    retention.size: 50GB     # Limit storage usage
    
remote_write:
  - url: "https://prometheus-remote-write-endpoint"
    queue_config:
      max_samples_per_send: 1000
      max_shards: 200
```

## Grafana Dashboards: Visual Data Pipeline Insights

### Agent Health Dashboard

```json
{
  "dashboard": {
    "title": "Matillion Agent Health",
    "panels": [
      {
        "title": "Agent Status",
        "type": "stat",
        "targets": [
          {
            "expr": "sum(app_agent_status)",
            "legendFormat": "Running Agents"
          }
        ]
      },
      {
        "title": "Active Tasks Over Time",
        "type": "graph",
        "targets": [
          {
            "expr": "sum(app_active_task_count) by (pod)",
            "legendFormat": "{{pod}}"
          }
        ]
      },
      {
        "title": "Task Completion Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(app_completed_tasks_total[5m])",
            "legendFormat": "Tasks/sec"
          }
        ]
      }
    ]
  }
}
```

### Performance Analytics Dashboard

```json
{
  "dashboard": {
    "title": "Agent Performance Analytics",
    "panels": [
      {
        "title": "Average Task Duration",
        "type": "graph",
        "targets": [
          {
            "expr": "avg_over_time(app_task_duration_seconds[1h])",
            "legendFormat": "Avg Duration"
          }
        ]
      },
      {
        "title": "Memory Usage vs Task Count",
        "type": "graph",
        "targets": [
          {
            "expr": "container_memory_usage_bytes{pod=~'matillion-agent.*'}",
            "legendFormat": "Memory Usage"
          },
          {
            "expr": "app_active_task_count * 1000000",
            "legendFormat": "Task Count (scaled)"
          }
        ]
      }
    ]
  }
}
```

## Alerting: Proactive Issue Detection

### Critical Agent Alerts

```yaml
# Alert rules for Matillion agents
groups:
- name: matillion-agent-critical
  rules:
  - alert: AgentDown
    expr: app_agent_status == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Matillion agent is down"
      description: "Agent {{$labels.pod}} has been down for more than 1 minute"
      
  - alert: HighTaskBacklog
    expr: app_active_task_count > 100
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High task backlog detected"
      description: "Agent {{$labels.pod}} has {{$value}} active tasks"
      
  - alert: DatabaseConnectionsExhausted
    expr: app_open_sessions > 150
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Database connections exhausted"
      description: "Agent {{$labels.pod}} has {{$value}} open sessions"
```

### Performance Degradation Alerts

```yaml
- name: matillion-agent-performance
  rules:
  - alert: SlowTaskExecution
    expr: avg_over_time(app_task_duration_seconds[30m]) > 600
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "Task execution time degraded"
      description: "Average task duration is {{$value}}s over the last 30 minutes"
      
  - alert: HighErrorRate
    expr: rate(app_task_errors_total[5m]) > 0.1
    for: 3m
    labels:
      severity: critical
    annotations:
      summary: "High task error rate"
      description: "Error rate is {{$value}} errors per second"
      
  - alert: MemoryLeakDetected
    expr: increase(container_memory_usage_bytes{pod=~'matillion-agent.*'}[1h]) > 1073741824 and app_active_task_count < 5
    for: 15m
    labels:
      severity: warning
    annotations:
      summary: "Potential memory leak detected"
      description: "Memory usage increased by {{$value}} bytes with low task activity"
```

## Log Aggregation and Analysis

### Structured Logging Configuration

```yaml
# Fluent Bit configuration for agent logs
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
data:
  fluent-bit.conf: |
    [SERVICE]
        Flush         1
        Log_Level     info
        Daemon        off
        Parsers_File  parsers.conf

    [INPUT]
        Name              tail
        Path              /var/log/containers/matillion-agent*.log
        Parser            cri
        Tag               matillion.agent.*
        Refresh_Interval  5

    [FILTER]
        Name                kubernetes
        Match               matillion.agent.*
        Kube_URL            https://kubernetes.default.svc:443
        Kube_CA_File        /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        Kube_Token_File     /var/run/secrets/kubernetes.io/serviceaccount/token
        Merge_Log           On
        K8S-Logging.Parser  On
        K8S-Logging.Exclude Off

    [OUTPUT]
        Name  es
        Match matillion.agent.*
        Host  elasticsearch.logging.svc
        Port  9200
        Index matillion-agent-logs
```

### Log Analysis Queries

```json
{
  "elasticsearch_queries": {
    "error_analysis": {
      "query": {
        "bool": {
          "must": [
            {"match": {"kubernetes.labels.app": "matillion-agent"}},
            {"range": {"@timestamp": {"gte": "now-1h"}}},
            {"match": {"log": "ERROR"}}
          ]
        }
      },
      "aggs": {
        "error_types": {
          "terms": {
            "field": "log_parsed.error_type.keyword"
          }
        }
      }
    },
    "performance_analysis": {
      "query": {
        "bool": {
          "must": [
            {"match": {"kubernetes.labels.app": "matillion-agent"}},
            {"match": {"log": "TASK_COMPLETED"}},
            {"range": {"@timestamp": {"gte": "now-24h"}}}
          ]
        }
      },
      "aggs": {
        "avg_execution_time": {
          "avg": {
            "field": "log_parsed.execution_time"
          }
        }
      }
    }
  }
}
```

## Multi-Cloud Monitoring Strategies

### AWS CloudWatch Integration

```yaml
# CloudWatch Container Insights
apiVersion: v1
kind: ConfigMap
metadata:
  name: cwagentconfig
data:
  cwagentconfig.json: |
    {
      "logs": {
        "metrics_collected": {
          "prometheus": {
            "prometheus_config_path": "/etc/prometheusconfig/prometheus.yaml",
            "ecs_service_discovery": {
              "sd_frequency": "1m",
              "sd_result_file": "/tmp/cwagent_ecs_auto_sd.yaml"
            }
          }
        }
      },
      "metrics": {
        "namespace": "Matillion/Agent",
        "metrics_collected": {
          "cpu": {
            "measurement": [
              "cpu_usage_idle",
              "cpu_usage_iowait",
              "cpu_usage_user",
              "cpu_usage_system"
            ]
          },
          "mem": {
            "measurement": [
              "mem_used_percent"
            ]
          }
        }
      }
    }
```

### Azure Monitor Integration

```yaml
# Azure Monitor configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: container-azm-ms-agentconfig
data:
  schema-version: v1
  config-version: ver1
  log-data-collection-settings: |-
    [log_collection_settings]
       [log_collection_settings.stdout]
          enabled = true
          exclude_namespaces = ["kube-system"]
       [log_collection_settings.stderr]
          enabled = true
          exclude_namespaces = ["kube-system"]
  prometheus-data-collection-settings: |-
    [prometheus_data_collection_settings.cluster]
        interval = "1m"
        monitor_kubernetes_pods = true
        monitor_kubernetes_pods_namespaces = ["default", "matillion"]
    [prometheus_data_collection_settings.node]
        interval = "1m"
```

## Observability Best Practices

### Metric Naming Conventions

```python
# Consistent metric naming for data agents
METRIC_PATTERNS = {
    # Business metrics
    'app_active_task_count',           # Current workload
    'app_completed_tasks_total',       # Historical throughput
    'app_failed_tasks_total',          # Error tracking
    'app_task_duration_seconds',       # Performance
    
    # Resource metrics
    'app_open_sessions',               # Connection pooling
    'app_memory_usage_bytes',          # Memory consumption
    'app_cpu_usage_seconds_total',     # CPU utilization
    
    # Health metrics
    'app_agent_status',                # Service health
    'app_last_heartbeat_timestamp',    # Connectivity
    'app_build_info'                   # Version tracking
}
```

### Monitoring Lifecycle Management

```yaml
# Monitoring as Code with Terraform
resource "grafana_dashboard" "agent_health" {
  config_json = file("${path.module}/dashboards/agent-health.json")
  folder      = grafana_folder.matillion.id
}

resource "grafana_dashboard" "agent_performance" {
  config_json = file("${path.module}/dashboards/agent-performance.json")
  folder      = grafana_folder.matillion.id
}

resource "prometheus_rule_group" "agent_alerts" {
  name     = "matillion-agent-alerts"
  interval = "30s"
  rule {
    alert = "AgentDown"
    expr  = "app_agent_status == 0"
    for   = "1m"
    labels = {
      severity = "critical"
    }
    annotations = {
      summary = "Matillion agent is down"
    }
  }
}
```

### Cost-Effective Monitoring

```yaml
# Monitoring cost optimization
prometheus:
  retention: "30d"              # Balance history with storage costs
  scrape_interval: "30s"        # Reduce data points for non-critical metrics
  evaluation_interval: "30s"    # Reduce alerting overhead
  
  metric_relabeling_configs:
    # Drop high-cardinality metrics
    - source_labels: [__name__]
      regex: 'app_task_id_.*'    # Drop per-task metrics
      action: drop
    
    # Sample less critical metrics
    - source_labels: [__name__]
      regex: 'app_debug_.*'
      target_label: __tmp_sample_rate
      replacement: '0.1'         # Keep only 10% of debug metrics
```

## Troubleshooting Common Monitoring Issues

### Issue: Missing Metrics
**Symptoms**: Dashboards show no data or incomplete metrics
**Solutions**:
```bash
# Check metrics endpoint
kubectl port-forward svc/matillion-agent-metrics 8000:8000
curl http://localhost:8000/metrics

# Verify Prometheus scraping
kubectl logs deployment/prometheus-server -f

# Check service discovery
kubectl get endpoints matillion-agent-metrics
```

### Issue: High Cardinality Metrics
**Symptoms**: Prometheus consuming excessive memory/storage
**Solutions**:
```yaml
# Limit metric cardinality
metric_relabeling_configs:
  - source_labels: [task_id]
    regex: '.*'
    action: drop  # Remove high-cardinality labels

  - source_labels: [user_id]
    regex: '(.{8}).*'
    target_label: user_id_short
    replacement: '${1}...'  # Truncate long labels
```

### Issue: Alert Fatigue
**Symptoms**: Too many alerts, team ignoring notifications
**Solutions**:
```yaml
# Implement alert severity levels
groups:
- name: critical-only
  rules:
  - alert: AgentClusterDown
    expr: count(app_agent_status == 1) == 0
    
- name: warning-batched
  rules:
  - alert: PerformanceDegradation
    expr: avg_over_time(app_task_duration_seconds[1h]) > 300
    for: 30m  # Longer wait time for warnings
```

## Future Monitoring Enhancements

### Intelligent Alerting
- Machine learning-based anomaly detection
- Dynamic alert thresholds based on historical patterns
- Context-aware alert routing

### Advanced Analytics
- Predictive performance modeling
- Cost attribution per data pipeline
- Capacity planning recommendations

### Integration Ecosystem
- Direct integration with data catalog tools
- Pipeline lineage tracking
- Data quality metrics correlation

## Conclusion

Comprehensive monitoring and observability transform your Matillion agent deployment from a black box into a transparent, manageable system. With built-in metrics collection, Prometheus integration, Grafana dashboards, and intelligent alerting, you gain:

- **Proactive issue detection** before problems impact business operations
- **Performance optimization** through detailed metrics and analytics
- **Cost control** via resource usage monitoring and optimization
- **Operational confidence** with comprehensive health and status visibility

The monitoring infrastructure included in this repository provides enterprise-grade observability out of the box, allowing your team to focus on data pipeline success rather than infrastructure troubleshooting.

Ready to implement comprehensive monitoring? Start with the Kubernetes deployment for the richest metrics experience, or adapt the monitoring patterns to your AWS ECS or Azure AKS environment.