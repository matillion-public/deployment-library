# Changelog — matillion-runner chart

## 0.6.1

Azure and GCP runners now start under any Helm release name (DPC-58375).

### Fixed

- `values-azure.yaml` and `values-gcp.yaml` set `serviceAccount.name: ""`,
  which overrode the chart's `matillion-runner-sa` default with a name derived
  from the release. The Terraform in this repo creates its workload-identity
  trust for the fixed names `matillion-runner-sa` and
  `matillion-runner-script-runner-sa`. So the two only matched when the release
  was called `matillion-runner`; under any other name the runner couldn't obtain
  cloud credentials. On AKS the postStart `az login --identity` then failed, and
  kubelet restarted the pod indefinitely. The only visible error was a
  misleading `IllegalStateException: Shutdown in progress` from the JVM. Both
  overlays now leave the runner name to the chart default and pin the
  script-runner name.

### Upgrade notes

- No change for releases named `matillion-runner`: they already rendered these
  exact names.
- Installs that worked around this by changing the Terraform
  `runner_service_account_name` / `script_runner_service_account_name` (Azure)
  or `k8s_service_account_name` / `script_runner_k8s_service_account_name`
  (GCP) to match a release-derived name must now also set
  `serviceAccount.name` / `scriptRunner.serviceAccount.name` to that same name.
  Otherwise the service account is renamed on upgrade and the trust stops
  matching.
- AWS is unchanged. Its IAM trust matches `*-script-runner-sa`, and
  `values-aws.yaml` never overrode the runner name.

## 0.6.0

Exposes the runner's OpenTelemetry metrics endpoint alongside the deprecated
Micrometer one (DPC-58190). Runner images from cloud-agent-service DPC-55707
onwards serve the OpenTelemetry Java agent's Prometheus exporter on
`:9464/metrics`, with `matillion_agent_*` names and JVM and process metrics. The
Micrometer `:8080/actuator/prometheus` endpoint (`app_*`) stays as a stopgap
until product sets a cutover date, so both are supported until then.

Defaults leave every existing consumer on the legacy endpoint. The annotations
still advertise `/actuator/prometheus`, and the HPA still scales on `app_*`. The
only rendered differences are a second container port and a second port in the
Prometheus ingress rule.

### Added

- `metrics.legacy.{enabled,port,path}` and `metrics.otel.{enabled,port,path}`:
  whether the chart exposes each endpoint to Prometheus (container port and
  NetworkPolicy ingress). `metrics.otel.port` is also passed to the runner as
  `OTEL_EXPORTER_PROMETHEUS_PORT`, so the exporter can't bind a different port
  from the one the chart opens.
- `metrics.annotationTarget` (`legacy` | `otel`): which endpoint the
  `prometheus.io/*` pod annotations advertise. Annotations can describe only
  one endpoint, so an annotation-driven scraper sees only the target. Scraping
  both needs an explicit job for the other, which the prometheus chart (0.4.0)
  provides.
- `hpa.metricSource` (`legacy` | `otel`): which metrics the HPA scales on.
  `otel` reads `matillion_agent_task_running` / `matillion_agent_request_active`,
  which the prometheus chart's adapter serves from 0.4.0. Both sources count the
  same in-flight work, so `hpa.metrics.target` needs no change when switching.

### Changed

- The Prometheus NetworkPolicy ingress rule now lists one port per exposed
  endpoint. With neither exposed, the rule is dropped rather than rendered with
  no ports, because an empty port list admits every port.

### Upgrade notes

- Contradictory settings fail the render instead of producing a runner whose
  HPA silently sits at `minReplicas`: `hpa.metricSource` or
  `metrics.annotationTarget` naming a disabled endpoint, or an unknown value
  for either.
- `metrics.otel.enabled=false` withdraws the chart's exposure of the endpoint.
  It does not stop the runner serving it inside the pod; that is controlled by
  the image.
- An image older than DPC-55707 has nothing listening on 9464. That's harmless
  while `hpa.metricSource=legacy`: the second scrape target reports down and
  nothing reads it. Don't switch `hpa.metricSource` to `otel` until the image
  serves the endpoint.

## 0.5.0

Non-IRSA AWS credential sources, caller-supplied library volumes, and an
explicit AWS region (DPC-54796, DPC-55696).

The chart previously offered exactly two ways to get AWS credentials to the
pods: the IRSA annotation, or long-lived access keys via `aws.local.enabled`.
Clusters whose platform layer assigns AWS permissions per node rather than per
service account — DuploCloud, and hand-rolled clusters predating IRSA — had
neither. Static keys are a worse posture than the node instance profile such a
cluster already has, so the only available workaround was the wrong one.

### Added

- `serviceAccount.credentialSource` — `irsa`, `node` or `static`. `node` writes
  no `eks.amazonaws.com/role-arn` annotation, so the AWS SDK falls through its
  provider chain to IMDS and picks up the EC2 node instance profile.
- `serviceAccount.create` and `scriptRunner.serviceAccount.create` — set false to
  bind the pods to a service account managed outside this release, rather than
  having the chart own it.
- `extraVolumes`, `extraVolumeMounts` and `initContainers` on both the agent and
  the script runner. Empty by default, so nothing renders for existing releases.
  These make it possible to supply Python libraries from an image the customer
  builds, as an alternative to staging them in object storage and pointing
  `EXTENSION_LIBRARY_LOCATION` at the prefix — an interpreter-loaded code path
  that some security reviews will not accept at rest in a bucket.
- `aws.region` — sets `AWS_REGION` and `AWS_DEFAULT_REGION` on both containers,
  on every credential source. Nothing in the cluster supplies one: IRSA and the
  node profile deliver credentials but not a region, so a pod can hold valid
  credentials and still fail at client construction with `NoRegionError`. Falls
  back to `aws.local.region` where that is already set. Left empty, no region
  variables render at all, which is the previous behaviour.
- Post-install NOTES per credential source: what the node profile needs to be
  granted, that static keys have a better alternative where the nodes carry an
  instance profile, and a warning when `roleArn` is set but ignored because
  `credentialSource` is not `irsa`. A `serviceAccount.create: false` release is
  told that its identity is managed outside the release and that `helm upgrade`
  cannot fix a wrong one.

### Upgrade notes

**No breaking change.** Every new value defaults to the previous behaviour:
`credentialSource` empty resolves to `irsa`, or to `static` when
`aws.local.enabled` is true, so a release that has never heard of this key
renders as it did on 0.4.0. The volume and region values are empty by default.

`credentialSource: node` has to be selected explicitly — blanking `roleArn` does
not get you there, and never did. While the annotation is present the EKS pod
identity webhook injects `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE`, and
the web-identity provider sits *ahead* of IMDS in the credential chain. An
annotation naming a role the pod cannot assume therefore fails outright rather
than degrading to the node profile. That is the whole reason this is an opt-in
value rather than something inferred from an empty `roleArn`.

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
