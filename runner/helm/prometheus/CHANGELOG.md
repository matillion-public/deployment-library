# Changelog — prometheus chart

## 0.4.0

Scrapes the runner's OpenTelemetry metrics endpoint alongside the deprecated
Micrometer one, and serves both sets of HPA metrics from the adapter
(DPC-58191). Also moves the adapter to a multi-arch image (DPC-58207). Pairs
with runner chart 0.6.0.

### Added

- A second scrape job, `matillion-runner-otel`, for `:9464/metrics`. It uses
  the same discovery as the existing job (`config.scrapeNamespaces` and
  `config.scrapePodLabelRegex`), so every tenant scraped on one endpoint is
  scraped on the other. Both jobs are rendered from one definition and can't
  drift apart.
- `config.legacy.{enabled,port,path}` and `config.otel.{enabled,port,path}` to
  turn each job on or off, for the cutover.
- `config.otel.dropTargetInfo` (default `true`): `target_info` is not stored.
  It carries the runner's resource attributes, including the full JVM command
  line, which can hold credentials passed as system properties.
- `config.otel.keepMetricsRegex`: optionally keep only matching metric names
  from the OTel job. The endpoint is unfiltered, with about 200 series per pod
  against about 11 on legacy, measured on EKS.
- Adapter rules for `matillion_agent_task_running` and
  `matillion_agent_request_active`, read from the exporter's `_unit`-suffixed
  series. They're served alongside the `app_*` rules, so each runner release
  chooses with `hpa.metricSource` and tenants on a shared Prometheus can
  migrate one at a time.

### Changed

- `adapter.prometheusAdapter.image.repository` now defaults to
  `registry.k8s.io/prometheus-adapter/prometheus-adapter` rather than
  `gcr.io/k8s-staging-prometheus-adapter/prometheus-adapter-amd64` (DPC-58207).
  The old default was the project's staging registry and an amd64-only build.
  On an arm64 node the adapter failed with `exec format error`, the custom
  metrics API went unavailable and the runner HPA stopped scaling, with nothing
  in the runner's own logs to explain why. The tag stays at `v0.12.0`.
- The egress policy opens one port per scraped endpoint, in both the
  same-namespace rule and every `networkPolicy.additionalScrapeNamespaces`
  rule. When neither job is composed (both disabled, or `config.prometheusYml`
  set) it opens both runner ports rather than render an empty port list, which
  would admit every port.

### Upgrade notes

- Clusters with restricted egress must allow `registry.k8s.io`, and the mirrors
  it redirects to, in place of `gcr.io` for the adapter image. Installs that
  mirror images privately and already override
  `adapter.prometheusAdapter.image.repository` are unaffected.
- The `matillion-runner` job renders byte-identically to 0.3.0, so dashboards,
  alerts and recording rules keyed on it are unaffected.
- Against a runner image without the exporter (older than DPC-55707),
  `matillion-runner-otel` reports `up == 0`. Nothing else changes, and nothing
  reads it while `hpa.metricSource=legacy`.
- `config.prometheusYml` overrides are still used verbatim. To scrape both
  endpoints, add a `matillion-runner-otel` job to the override yourself.

## 0.3.0

Multi-namespace scrape discovery for the shared runner platform (DPC-53846).

Defaults are unchanged: the chart still discovers runners in the `matillion`
namespace using the literal `matillion-runner-pods` pod label, and the rendered
manifest is identical to 0.2.0 apart from the `helm.sh/chart` version label.

### Added

- `config.scrapeNamespaces` — namespaces the runner scrape job discovers pods
  in. An empty list means every namespace; the pod-list RBAC is already a
  `ClusterRole`, so no permission changes are needed.
- `config.scrapePodLabelRegex` — regex matched against the pod's `app` label.
  Each release labels its pods `<release>-matillion-runner-pods`, so a shared
  Prometheus generally wants `.*matillion-runner-pods`.
- `networkPolicy.additionalScrapeNamespaces` — namespaces beyond Prometheus's
  own that the pod may reach. The pre-existing egress rule uses a bare
  `podSelector`, which is namespace-local, so multi-namespace *discovery* alone
  would find targets the policy then blocks.
- `networkPolicy.runnerPodSelector` — pod selector applied within those
  namespaces. Set to `null` (not `{}`, which Helm coalesces away) to admit any
  pod and let service discovery do the filtering.

### Changed

- `config.prometheusYml` now defaults to empty, and the config is composed from
  the settings above. Setting it to a complete `prometheus.yml` still uses that
  value verbatim, so existing overrides of this key are unaffected.

### Upgrade notes

`config.scrapeNamespaces` and `networkPolicy.additionalScrapeNamespaces` must
agree. A tenant namespace present in one but not the other fails quietly rather
than loudly: the target is either never discovered or discovered and then
blocked, the metric is empty either way, and the HPA that depends on it sits at
`minReplicas` with nothing in any log to explain why. `README.md` has a command
for verifying every tenant is actually being scraped after rollout.
