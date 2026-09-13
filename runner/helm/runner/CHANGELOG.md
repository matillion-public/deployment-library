# Changelog — matillion-runner chart

## 0.4.0

Close the bypassed-workload-identity hole on GCP and Azure (DPC-55764).

A GCP deployment could be installed with no cloud identity at all, silently.
`gcp.workloadIdentity.serviceAccountEmail` was only `required` *inside* the
`gcp.workloadIdentity.enabled` branch, so setting `enabled: false` skipped the
check and rendered a ServiceAccount with no annotation. The install succeeded
and the runner came up unable to reach Secret Manager or GCS. Azure had the
identical shape. AWS never did: `serviceAccount.roleArn` is `required` unless
`aws.local.enabled` names an alternative credential source.

That is not a hypothetical: a GKE customer deployed by hand rather than through
the terraform on 2026-08-28, had no `runner_workload_sa_email` output to supply,
and `enabled: false` was the obvious way past the error. The runner had no
access to the service account or the project, and nothing in the install said so.

### Added

- `gcp.nodeIdentity.enabled` and `azure.nodeIdentity.enabled` — the one
  sanctioned way to install without per-workload identity on each cloud: the pod
  inherits the node pool's service account (GKE) or kubelet managed identity
  (AKS) from the instance metadata service. Named rather than implied, so
  `helm get values` always says which identity the pod is using.
- **Rendering fails** when a GCP or Azure deployment names no identity at all,
  with a message stating the runtime consequence and both ways out. This matches
  the AWS behaviour, which has never been sidesteppable.
- Post-install NOTES now print the commands to verify the binding actually took
  effect, per cloud — the annotation alone proves nothing, because the other half
  of the binding (IAM policy binding, federated credential, role trust policy)
  lives outside the release. On the `nodeIdentity` paths the NOTES say loudly
  that the runner has no workload identity and what that costs.
- `runner/gcp/gke/README.md` gains "Identity is not optional" — the rule that a
  GKE runner deployed outside the terraform has no identity by default — and
  "Binding an identity to a runner already installed", a runbook for fixing one
  in place without reinstalling.

### Fixed

- `values.yaml` pointed at a non-existent terraform output
  (`agent_workload_sa_email`). The real one is `runner_workload_sa_email`. An
  operator following that comment found nothing, which is the first step on the
  path to `enabled: false`.

### Upgrade notes

**Breaking for one configuration**, deliberately. A release currently running
with `gcp.workloadIdentity.enabled: false`, or with Azure workload identity and
service principal both off, will fail to render on upgrade. That release has no
cloud identity today — the failure is surfacing an existing fault, not creating
one. Either supply the identity, or add `nodeIdentity.enabled: true` to state
that inheriting the node's identity is intended.

Every other configuration renders byte-identically to 0.3.0 apart from the
`helm.sh/chart` version label and the added NOTES output.

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
