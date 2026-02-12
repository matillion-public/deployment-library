# Matillion Agent Metrics Exporter (Deprecated)

> **Note:** The metrics exporter sidecar has been **deprecated**. The Matillion Agent now natively exposes Prometheus-compatible metrics at `/actuator/prometheus` on port 8080. No sidecar container is required.

## Native Prometheus Endpoint

The agent exposes metrics directly at:

```
http://<agent-host>:8080/actuator/prometheus
```

### Metrics Provided

| Metric Name | Type | Description |
|-------------|------|-------------|
| `app_active_request_count` | Gauge | Number of active API requests |
| `app_active_task_count` | Gauge | Number of currently executing tasks |
| `app_agent_connected` | Gauge | Agent connection state (1.0=connected, 0.0=not connected) |
| `app_agent_status` | Gauge | Agent status (1.0=RUNNING, 2.0=PENDING_SHUTDOWN, 3.0=SHUTTING_DOWN, 0.0=not running) |
| `app_open_sessions_count` | Gauge | Number of open database sessions |
| `app_version` | Gauge | Application version information (build_timestamp, commit_hash, version labels) |

### Example Output

```prometheus
# HELP app_active_request_count The number of active requests
# TYPE app_active_request_count gauge
app_active_request_count 0.0
# HELP app_active_task_count The number of active tasks
# TYPE app_active_task_count gauge
app_active_task_count 0.0
# HELP app_agent_connected Shows the state of the agent's connection to the Data Productivity Cloud (1.0 for connected, 0.0 if not connected)
# TYPE app_agent_connected gauge
app_agent_connected 1.0
# HELP app_agent_status Shows the status of the agent (1.0 for RUNNING, 2.0 for PENDING_SHUTDOWN, 3.0 for SHUTTING_DOWN, 0.0 if not running)
# TYPE app_agent_status gauge
app_agent_status 1.0
# HELP app_open_sessions_count The number of open sessions
# TYPE app_open_sessions_count gauge
app_open_sessions_count 0.0
# HELP app_version Application version information
# TYPE app_version gauge
app_version{build_timestamp="1770124071641",commit_hash="<unknown version>",version="0.0.1-GB-DT-MX19C-local"} 1.0
```

### Prometheus Scrape Configuration

```yaml
# Pod annotations (configured automatically by the Helm chart)
prometheus.io/scrape: "true"
prometheus.io/port: "8080"
prometheus.io/path: "/actuator/prometheus"
```

## Legacy Sidecar Files

The files in this directory (`custom_metics_exporter.py`, `Dockerfile.sidecar`, etc.) are retained for reference but are no longer required for new deployments.
