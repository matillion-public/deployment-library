# Matillion Agent Metrics Exporter

A lightweight **Prometheus-compatible metrics exporter** that runs as a sidecar container alongside the Matillion DPC Agent, providing observability and monitoring capabilities.

## Overview

The metrics exporter collects operational metrics from the Matillion Agent's actuator endpoint and exposes them in Prometheus format for monitoring and alerting.

## Metrics Provided

| Metric Name | Type | Description |
|-------------|------|-------------|
| `app_version_info` | Gauge | Application build information (version, commit, timestamp) |
| `app_agent_status` | Gauge | Agent running status (1=running, 0=stopped) |
| `app_active_task_count` | Gauge | Number of currently executing tasks |
| `app_active_request_count` | Gauge | Number of active API requests |
| `app_open_sessions_count` | Gauge | Number of open database sessions |

### Example Output

```prometheus
# HELP app_version_info Application version information.
# TYPE app_version_info gauge
app_version_info{version="1.2.3", commit_hash="abc123", build_timestamp="1234567890"} 1

# HELP app_agent_status Shows if the agent is running. (1 for running, 0 for not)
# TYPE app_agent_status gauge
app_agent_status 1

# HELP app_active_task_count The number of active tasks.
# TYPE app_active_task_count gauge
app_active_task_count 5

# HELP app_active_request_count The number of active requests.
# TYPE app_active_request_count gauge
app_active_request_count 3

# HELP app_open_sessions_count The number of open sessions.
# TYPE app_open_sessions_count gauge
app_open_sessions_count 2
```

## Architecture

### Sidecar Pattern
```
┌─────────────────────────────────┐
│           Pod                   │
│  ┌──────────────┐               │
│  │    Agent     │               │
│  │    :8080     │               │
│  └──────────────┘               │
│           │                     │
│  ┌──────────────┐               │
│  │   Metrics    │  GET /metrics │
│  │   Exporter   │◄──────────────│
│  │    :8000     │               │
│  └──────────────┘               │
└─────────────────────────────────┘
```

The metrics exporter:
1. **Polls** the agent's actuator endpoint (`http://localhost:8080/actuator/info`)
2. **Transforms** JSON data into Prometheus format
3. **Serves** metrics on port 8000 at `/metrics` endpoint

## Docker Image

### Building

```bash
# Build using the sidecar Dockerfile
docker build -f Dockerfile.sidecar -t metrics-exporter:latest .

# Multi-platform build
docker buildx build --platform linux/amd64,linux/arm64 \
  -f Dockerfile.sidecar -t metrics-exporter:latest .
```

### Base Image Security

The Docker image uses `python:3.12-alpine` for:
- **Minimal attack surface** (Alpine Linux)
- **Latest security patches** (Python 3.12)
- **Non-root execution** (runs as user `appuser`)
- **Small footprint** (~50MB final image)

### Running Standalone

```bash
# Start mock agent backend
docker run -d --name mock-agent -p 8080:80 nginx:alpine

# Configure mock response
docker exec mock-agent sh -c 'mkdir -p /usr/share/nginx/html/actuator'
docker exec mock-agent sh -c 'echo "{\"agentStatus\":\"RUNNING\"}" > /usr/share/nginx/html/actuator/info'

# Run metrics exporter
docker run -d --name metrics-exporter \
  -p 8000:8000 --link mock-agent:localhost \
  metrics-exporter:latest

# Test metrics endpoint
curl http://localhost:8000/metrics
```

## Testing

### Unit Tests

```bash
# Install test dependencies
pip install -r requirements.txt

# Run unit tests with coverage
pytest test_custom_metrics_exporter.py -v --cov=custom_metics_exporter

# Generate coverage report
pytest --cov=custom_metics_exporter --cov-report=html
```

### Integration Tests

```bash
# Run integration tests (requires running exporter)
pytest tests/integration/test_metrics_endpoint.py -v
```

### Test Coverage

The test suite covers:
- **HTTP endpoint functionality**
- **Prometheus format compliance**
- **Error handling and recovery**
- **Data transformation accuracy**
- **Edge cases and missing data**

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `METRICS_ENDPOINT` | Agent actuator URL | `http://localhost:8080/actuator/info` |
| `PORT` | Metrics server port | `8000` |

### Kubernetes Deployment

The metrics exporter is designed to run as a sidecar in the same pod as the Matillion Agent:

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
      - name: agent
        image: matillion/agent:latest
        ports:
        - containerPort: 8080
      
      - name: metrics-exporter
        image: brbajematillion/metrics-sidecar:latest
        ports:
        - containerPort: 8000
          name: metrics
        resources:
          limits:
            cpu: 100m
            memory: 128Mi
          requests:
            cpu: 50m
            memory: 64Mi
```

## Monitoring Setup

### Prometheus Configuration

```yaml
# prometheus.yml
scrape_configs:
- job_name: 'matillion-agent'
  kubernetes_sd_configs:
  - role: pod
  relabel_configs:
  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
    action: keep
    regex: true
  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_port]
    action: replace
    target_label: __address__
    regex: (.+)
    replacement: ${1}:8000
```

### Grafana Dashboard

Key metrics to monitor:
- **Agent Uptime**: `app_agent_status`
- **Task Load**: `app_active_task_count`
- **Request Volume**: `app_active_request_count` 
- **Resource Usage**: `app_open_sessions_count`

### Alerting Rules

```yaml
# Example alerting rules
groups:
- name: matillion-agent
  rules:
  - alert: AgentDown
    expr: app_agent_status == 0
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Matillion Agent is down"
  
  - alert: HighTaskLoad
    expr: app_active_task_count > 10
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High task load on Matillion Agent"
```

## Development

### Local Development

```bash
# Install dependencies
pip install -r requirements.txt

# Run locally (requires agent on localhost:8080)
python custom_metics_exporter.py

# Test metrics endpoint
curl http://localhost:8000/metrics
```

### Code Structure

```
agent/helm/image/
├── custom_metics_exporter.py    # Main Flask application
├── test_custom_metrics_exporter.py  # Unit tests
├── requirements.txt             # Python dependencies
├── Dockerfile.sidecar          # Multi-stage build
├── pytest.ini                 # Test configuration
└── README.md                   # This file
```

### Adding New Metrics

1. **Extend the data source** in `fetch_metrics()`
2. **Add conversion logic** in `convert_to_prometheus()`
3. **Write unit tests** for the new metric
4. **Update documentation**

Example:
```python
def convert_to_prometheus(metrics):
    prom_metrics = []
    
    # Add new metric
    queue_size = metrics.get("queueSize", 0)
    prom_metrics.append('# HELP app_queue_size Size of the task queue.')
    prom_metrics.append('# TYPE app_queue_size gauge')
    prom_metrics.append(f'app_queue_size {queue_size}')
    
    return '\n'.join(prom_metrics)
```

## Error Handling

### Graceful Degradation

The metrics exporter handles errors gracefully:

- **Connection failures**: Logs error and exits (letting Kubernetes restart)
- **Invalid JSON**: Returns default metric values
- **Missing fields**: Uses sensible defaults (0 for counters, "unknown" for strings)

### Health Checks

The metrics endpoint serves as a health check:
- **HTTP 200**: Service is healthy and metrics available
- **Connection refused**: Service is down (detected by Prometheus)

## Security Considerations

- **Non-root execution**: Runs as unprivileged user `appuser`
- **Minimal dependencies**: Only Flask and Requests libraries
- **No persistent storage**: Stateless operation
- **Local communication only**: Only connects to localhost:8080
- **Security scanning**: Automated vulnerability scanning in CI/CD

## Performance

### Resource Usage
- **CPU**: ~5-10m under normal load
- **Memory**: ~30-50MB RSS
- **Network**: Minimal (local HTTP calls only)

### Scalability
- **Polling frequency**: 1 request per Prometheus scrape (typically 15-30s)
- **Response time**: < 100ms typical
- **Concurrent requests**: Handled by Flask's threading

### Code Quality

- **Type hints**: Use Python type annotations
- **Testing**: Maintain >90% test coverage
- **Linting**: Follow PEP 8 style guidelines
- **Documentation**: Update README for changes