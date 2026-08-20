# Changelog — matillion-runner chart

## 0.3.0

Multi-tenant chart parameterisation (DPC-53846 item 4). Onboarding a business
unit is now a values file rather than a chart change.

Off by default: with `commonLabels` and `podAnnotations` unset the rendered
manifest is unchanged from 0.2.0 apart from the `helm.sh/chart` version label.

### Added

- `commonLabels` — labels applied to every resource the chart creates and to the
  runner pods, for tenant attribution (business unit, cost centre, owning team).
- `podAnnotations` — merged with the existing `prometheus.io/*` scrape
  annotations rather than replacing them.
- `values-tenant-example.yaml` — worked example of onboarding a business unit,
  documenting what must be unique per tenant and what must never change.

### Upgrade notes

`commonLabels` rejects `app`, `app.kubernetes.io/name` and
`app.kubernetes.io/instance` at template time. This is deliberate: those three
form the Deployment's `spec.selector`, which Kubernetes treats as immutable, so
a label reaching it would make `helm upgrade` of an existing release fail
outright rather than roll. Use your own prefix for attribution.

## 0.2.0

Shared multi-tenant runner platform (DPC-53846).

Every addition here is values-gated and **off by default**. Upgrading without
changing any values produces a rendered manifest identical to 0.1.0 apart from
the `helm.sh/chart` version label, so nothing changes for existing consumers
until they opt in.

### Added

- `topologySpread` — spread replicas across availability zones. Defaults to
  `ScheduleAnyway`; `DoNotSchedule` would leave pods Pending on a single-zone
  cluster. Only useful if the nodes span zones (on AKS that needs
  `node_pool_zones` — see `modules/azure/aks/readme.md`).
- `affinity` — pod affinity/anti-affinity, passed through verbatim.
- `podDisruptionBudget` — voluntary-disruption budget, expressed as
  `maxUnavailable`. **Rendering fails** if enabled when the workload's replica
  floor is below 2: such a budget permits zero evictions and hangs node drains
  indefinitely, so it is rejected rather than silently skipped.
- `readinessProbe` / `livenessProbe`. The default liveness failure window
  (`periodSeconds x failureThreshold`) deliberately outlasts the 43200s
  termination grace period, so a pod draining in-flight tasks is never killed
  early. NOTES warns if that relationship is broken.

### Changed

- NOTES now warns when `gracePeriodSeconds` is lowered below the runner's own
  43200s shutdown timeout (which turns a lossless planned failover into a lossy
  one), when a liveness probe would undercut the grace period, and when
  `topologySpread` is enabled without a PodDisruptionBudget.

### Upgrade notes

Enabling `podDisruptionBudget` on a workload whose replica floor is below 2 is
rejected at template time rather than silently skipped. Raise `hpa.minReplicas`
(or `dpcAgent.replicas` when the HPA is disabled) to at least 2, or leave the
budget off.
