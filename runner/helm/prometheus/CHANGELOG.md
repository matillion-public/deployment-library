# Changelog — prometheus chart

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
