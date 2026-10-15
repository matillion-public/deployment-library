# Runner Metrics: Moving from `/actuator/prometheus` to the OpenTelemetry Endpoint

The Matillion runner now serves its Prometheus metrics from two endpoints. The
original Micrometer endpoint is deprecated and will be removed once Matillion
sets a cutover date. Until then both run side by side, so you can move
dashboards, alerts and autoscaling across at your own pace.

This guide covers what each endpoint serves, how the old metric names map to
the new ones, and what to change in the Helm charts and your own Prometheus.

## The two endpoints

| | Legacy (deprecated) | OpenTelemetry (new standard) |
|---|---|---|
| URL | `:8080/actuator/prometheus` | `:9464/metrics` |
| Produced by | Spring Micrometer | OpenTelemetry Java agent's Prometheus exporter |
| Metric names | `app_*` | `matillion_agent_*`, plus JVM metrics |
| Filtered | Yes, to the `app_*` gauges (about 11 series per pod) | No (about 200 series per pod) |
| Runner image | All versions | Built from cloud-agent-service DPC-55707 onwards |

The OpenTelemetry port can be changed with the runner chart's
`metrics.otel.port`. The chart passes it to the runner as
`OTEL_EXPORTER_PROMETHEUS_PORT`, so the two always agree.

## Metric name mapping

The OpenTelemetry exporter turns dots into underscores and appends the
instrument's unit, which for these gauges is `unit`. So `matillion.agent.status`
becomes `matillion_agent_status_unit`. Every series also carries an
`otel_scope_name` label.

These names were confirmed against a DPC-55707 runner image on EKS and AKS.

| Legacy | OpenTelemetry | Labels on the OpenTelemetry series |
|---|---|---|
| `app_agent_status` | `matillion_agent_status_unit` | `account_id` |
| `app_agent_connected` | `matillion_agent_connected_unit` | `account_id` |
| `app_active_task_count` | `matillion_agent_task_running_unit` | `matillion_agent_cloud_provider` |
| `app_active_request_count` | `matillion_agent_request_active_unit` | `account_id` |
| `app_open_sessions_count` | `matillion_agent_open_sessions_unit` | `matillion_agent_cloud_provider` |
| `app_version_info` | `matillion_agent_version_unit` | `account_id`, `version`, `commit_hash`, `build_timestamp` |

Values match: status is `1` running, `2` pending shutdown, `3` shutting down and
`0` otherwise, and connected is `1` or `0`, on both endpoints.

The version metric's name depends on the exposition format. The runner
registers `app_version_info`, but the legacy endpoint serves it as
`app_version` to plain-text scrapers such as `curl`. Likewise the OpenTelemetry
exporter drops `.info` from `matillion.agent.version.info`. Check
which name your Prometheus actually stores before rewriting a version query.

**Label sets differ between metrics.** Task count, open sessions and task
queued come from a different part of the runner than the other gauges, and
carry `matillion_agent_cloud_provider` (`AWS`, `AZURE`, `GCP`) instead of
`account_id`. If a query or alert groups by `account_id`, check which metric it
reads.

### Only on the OpenTelemetry endpoint

- `matillion_agent_task_queued_unit`: tasks waiting for a slot.
- `matillion_agent_busyness_score`: the runner's own load estimate.
- `matillion_agent_sse_*`: health of the runner's connection to Matillion
  (connect attempts, duration histogram, health-check outcomes).
- JVM metrics from the OpenTelemetry agent, including `jvm_memory_used_bytes`,
  `jvm_memory_committed_bytes`, `jvm_memory_limit_bytes`,
  `jvm_gc_duration_seconds` (histogram), `jvm_thread_count`,
  `jvm_class_count`, `jvm_cpu_time_seconds_total` and
  `jvm_cpu_recent_utilization`.

## Using the Helm charts

Runner chart 0.6.0 and prometheus chart 0.4.0 support both endpoints. The
defaults change nothing for existing installs: the scrape annotations and the
HPA stay on the legacy endpoint.

### What you get by default

- The runner pod declares both ports, and its NetworkPolicy lets the Prometheus
  namespace reach both.
- The bundled Prometheus runs two scrape jobs: `matillion-runner` (legacy,
  unchanged) and `matillion-runner-otel` (new). Check both are up with
  `up{job=~"matillion-runner.*"}`.
- The adapter serves both sets of HPA metrics: `app_active_task_count` /
  `app_active_request_count`, and `matillion_agent_task_running` /
  `matillion_agent_request_active`.
- The HPA still scales on `app_active_task_count` and `app_active_request_count`.

### Moving autoscaling to the new metrics

Upgrade the runner to an image that serves `:9464/metrics` first. Then set, in
the runner chart:

```yaml
hpa:
  metricSource: otel
```

Both sources count the same in-flight work, so `hpa.metrics.target` doesn't
need retuning. On a shared Prometheus each runner release switches
independently, because the adapter serves both sets at once.

Don't switch while the runner image is older than DPC-55707. Nothing listens on
9464 there, so the HPA would have no metric to read and stay at its current
size. The chart can't detect the image version, so it can't stop you.

### Moving the scrape annotations

The `prometheus.io/*` annotations can describe only one endpoint. They stay on
legacy until cutover so annotation-driven scrapers aren't moved to different
metric names without warning. Once your dashboards and alerts use the new names:

```yaml
metrics:
  annotationTarget: otel
```

### Keeping the bundled Prometheus lean

The OpenTelemetry endpoint isn't filtered, and the bundled Prometheus scrapes
every 5 seconds with no persistent volume. If it only serves the HPA, keep just
the runner's own metrics:

```yaml
config:
  otel:
    keepMetricsRegex: "matillion_agent_.*"
```

`target_info` is dropped by default (`config.otel.dropTargetInfo: true`). It
carries the runner's full JVM command line, which can include values passed as
system properties.

### Settings the charts reject

These fail `helm install` / `helm upgrade` with an explanation, rather than
deploying a runner whose HPA silently stops scaling:

- `hpa.metricSource: otel` with `metrics.otel.enabled: false`
- `hpa.metricSource: legacy` with `metrics.legacy.enabled: false`
- `metrics.annotationTarget` pointing at a disabled endpoint
- any value other than `legacy` or `otel` for either setting

## Scraping from your own Prometheus

If you scrape runners with your own Prometheus rather than the bundled chart,
add a job for the new endpoint next to the existing one. Annotation-based
discovery only sees the endpoint the annotations name, so name the port
explicitly:

```yaml
scrape_configs:
  - job_name: matillion-runner-otel
    kubernetes_sd_configs:
      - role: pod
        namespaces:
          names: [matillion]
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        action: keep
        regex: .*matillion-runner-pods
      - source_labels: [__meta_kubernetes_pod_ip]
        target_label: __address__
        replacement: $1:9464
      - target_label: __metrics_path__
        replacement: /metrics
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: target_info
        action: drop
```

If your runner chart has `networkPolicy.enabled: true`, set
`networkPolicy.prometheusNamespace` to your Prometheus's namespace. That
namespace needs a `name` label, as the policy matches on it.

### Rewriting queries

Swap the metric name, then check any grouping labels against the mapping table:

```promql
# Before
sum(app_active_task_count) by (pod)
app_agent_status == 0

# After
sum(matillion_agent_task_running_unit) by (pod)
matillion_agent_status_unit == 0
```

## ECS and Azure Container Apps

Neither deployment exposes the OpenTelemetry endpoint outside the task or
container today:

- **ECS:** no security group opens 9464. The optional saturation monitor reads
  the runner's `actuator` JSON endpoints, not Prometheus, and is unaffected.
- **Azure Container Apps:** the runner container app has no ingress.

Support for both is tracked separately (DPC-58192).

## Cutover

Matillion will announce the date the legacy endpoint is removed. Before then,
make sure that:

1. Dashboards and alerts use the `matillion_agent_*` names.
2. `hpa.metricSource` is `otel` on every runner release.
3. `metrics.annotationTarget` is `otel`, or your scrapers name port 9464
   directly.

After cutover, `metrics.legacy` and `config.legacy` are removed from the charts.
Port 8080 stays, because it also serves the health probes.

## Related

- [Autoscaling Matillion Runners](./autoscaling-matillion-agents.md)
- [Monitoring and Observability](./monitoring-and-observability.md)
- Runner chart values: [`runner/helm/README.md`](../runner/helm/README.md)
- Prometheus chart values: [`runner/helm/prometheus/README.md`](../runner/helm/prometheus/README.md)
