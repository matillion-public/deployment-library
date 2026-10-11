{{/*
Expand the name of the chart.
*/}}
{{- define "matillion-runner.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "matillion-runner.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "matillion-runner.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "matillion-runner.labels" -}}
helm.sh/chart: {{ include "matillion-runner.chart" . }}
{{ include "matillion-runner.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{- include "matillion-runner.commonLabels" $ | nindent 0 }}
{{- end }}
{{- end }}

{{/*
Caller-supplied labels, applied to every resource the chart creates and to the
runner pods, so a shared cluster can attribute workloads to a business unit
without the chart knowing anything about tenants.

Deliberately NOT part of matillion-runner.selectorLabels. A Deployment's
spec.selector is immutable: a label that reaches it turns `helm upgrade` of an
existing release into an outright failure rather than a rolling update. These
are additive only, and validated below to keep it that way.
*/}}
{{- define "matillion-runner.commonLabels" -}}
{{- $reserved := list "app" "app.kubernetes.io/name" "app.kubernetes.io/instance" }}
{{- range $key, $value := .Values.commonLabels }}
{{- if has $key $reserved }}
{{- fail (printf "commonLabels may not set %q. That label is part of the Deployment's immutable spec.selector, so overriding it makes `helm upgrade` of an existing release fail instead of rolling. Use a different key — commonLabels are for additive attribution such as business-unit or cost-centre." $key) }}
{{- end }}
{{- end }}
{{- with .Values.commonLabels }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "matillion-runner.selectorLabels" -}}
app.kubernetes.io/name: {{ include "matillion-runner.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Name of the runner's service account.

The fallback is "<fullname>-sa", which is what serviceaccount.yaml and
deployment.yaml both spelled inline before this was centralised. An earlier
version of this helper fell back to "<fullname>" with no suffix and was never
referenced by any template, so the two spellings never had to agree; they do
now. serviceAccount.name is set in values.yaml, so the fallback only fires if a
caller blanks it.

Applies whether or not the chart creates the object: with
serviceAccount.create=false this is the pre-existing account the pods bind to.
*/}}
{{- define "matillion-runner.serviceAccountName" -}}
{{- .Values.serviceAccount.name | default (printf "%s-sa" (include "matillion-runner.fullname" .)) }}
{{- end }}

{{/*
Name of the Script Runner's service account. Same shape as the runner's.
*/}}
{{- define "matillion-runner.scriptRunner.serviceAccountName" -}}
{{- .Values.scriptRunner.serviceAccount.name | default (printf "%s-sa" (include "matillion-runner.scriptRunner.fullname" .)) }}
{{- end }}

{{/*
Resolve where the pods get their AWS credentials. One of:

  irsa    annotate the SA with eks.amazonaws.com/role-arn and let the EKS pod
          identity webhook inject a web-identity token. The default, and what
          every existing release already does.
  node    no annotation, no injected credentials. The AWS SDK/CLI falls through
          its provider chain to IMDS and picks up the node instance profile.
          For clusters whose platform layer assigns AWS permissions per node
          rather than per service account (DuploCloud, and hand-rolled clusters
          predating IRSA).
  static  long-lived access keys from a chart-managed secret.

This has to be a resolved value rather than three independent booleans because
the annotation is not inert. When it is present the webhook injects AWS_ROLE_ARN
and AWS_WEB_IDENTITY_TOKEN_FILE, and the web-identity provider sits AHEAD of
IMDS in the credential chain — so an annotation naming a role the pod cannot
assume does not degrade to the node profile, it fails outright. "Leave roleArn
empty and hope" is therefore not a usable way to select the node profile, which
is why this is an explicit opt-in.

aws.local.enabled predates this and still works: it means static. Setting both
it and a contradictory credentialSource is an error rather than a precedence
puzzle.
*/}}
{{- define "matillion-runner.aws.credentialSource" -}}
{{- $valid := list "irsa" "node" "static" -}}
{{- $explicit := .Values.serviceAccount.credentialSource | default "" -}}
{{- $legacyStatic := .Values.aws.local.enabled | default false -}}
{{- if and $explicit (not (has $explicit $valid)) -}}
{{- fail (printf "serviceAccount.credentialSource is %q; must be one of irsa, node, static." $explicit) -}}
{{- end -}}
{{- if and $legacyStatic (and $explicit (ne $explicit "static")) -}}
{{- fail (printf "aws.local.enabled=true means static access keys, but serviceAccount.credentialSource is %q. Set one or the other: drop aws.local.enabled, or set credentialSource=static." $explicit) -}}
{{- end -}}
{{- if $explicit -}}
{{- $explicit -}}
{{- else if $legacyStatic -}}
static
{{- else -}}
irsa
{{- end -}}
{{- end }}

{{/*
Resolve the AWS region for the agent and the script runner.

Nothing in the cluster supplies this. IRSA and the node profile deliver
credentials but never a region, and the AWS SDKs treat the two as separate
concerns — so a pod can hold perfectly good credentials and still fail at client
construction with NoRegionError. Only the static path had a region at all, out of
the aws-local secret, which left every IRSA and node deployment without one
(DPC-55696).

Precedence:
  1. aws.region — applies on every credential source.
  2. aws.local.region — predates this and is required when aws.local.enabled, so
     it is honoured as the fallback rather than forcing static callers to repeat
     themselves in two places.

Empty is a valid answer and renders no region variables at all, which is the
pre-existing behaviour. Making this required would break every release already
running on IRSA at upgrade time, for the sake of a variable their scripts may
well be setting themselves.
*/}}
{{- define "matillion-runner.aws.region" -}}
{{- .Values.aws.region | default .Values.aws.local.region | default "" -}}
{{- end }}

{{/*
Normalize cloudProvider to lowercase for consistent comparisons
*/}}
{{- define "matillion-runner.cloudProvider" -}}
{{- .Values.cloudProvider | lower }}
{{- end }}

{{/*
Resolve the container resources block.

Precedence:
  1. .Values.dpcAgent.dpcAgent.resources, if non-empty (full override)
  2. .Values.runnerSizes[.Values.runnerSize] from the size map

runnerSize must be one of: small, medium, large, xlarge.
*/}}
{{- define "matillion-runner.resources" -}}
{{- $size := .Values.runnerSize | default "small" -}}
{{- $sizeMap := index .Values.runnerSizes $size -}}
{{- if not $sizeMap -}}
{{- fail (printf "runnerSize %q is not defined in .Values.runnerSizes — must be one of: small, medium, large, xlarge" $size) -}}
{{- end -}}
{{- $override := .Values.dpcAgent.dpcAgent.resources | default dict -}}
{{- if and (kindIs "map" $override) (gt (len $override) 0) -}}
{{- toYaml $override -}}
{{- else -}}
{{- toYaml $sizeMap -}}
{{- end -}}
{{- end }}

{{/*
The floor on the runner Deployment's replica count.

When the HPA is enabled it, not dpcAgent.replicas, owns the replica count, so the
floor is hpa.minReplicas. Used to decide whether a PodDisruptionBudget can safely
be rendered — a budget over a workload that can legitimately sit at one replica
permits no voluntary evictions at all and wedges node drains.
*/}}
{{- define "matillion-runner.minReplicas" -}}
{{- if .Values.hpa.enabled -}}
{{- .Values.hpa.minReplicas | int -}}
{{- else -}}
{{- .Values.dpcAgent.replicas | int -}}
{{- end -}}
{{- end }}

{{/*
Fully qualified name for the Shared Script Runner resources.
*/}}
{{- define "matillion-runner.scriptRunner.fullname" -}}
{{- printf "%s-script-runner" (include "matillion-runner.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Script Runner selector labels — runner selectorLabels plus a component marker so
NetworkPolicies can target script-runner pods distinctly from agent (runner) pods.
*/}}
{{- define "matillion-runner.scriptRunner.selectorLabels" -}}
{{ include "matillion-runner.selectorLabels" . }}
app.kubernetes.io/component: script-runner
{{- end }}

{{/*
Resolve the Script Runner container resources block.

Precedence:
  1. .Values.scriptRunner.resources, if non-empty (full override)
  2. .Values.runnerSizes[.Values.scriptRunner.size] from the shared size map

scriptRunner.size must be one of: small, medium, large, xlarge.
*/}}
{{- define "matillion-runner.scriptRunner.resources" -}}
{{- $size := .Values.scriptRunner.size | default "small" -}}
{{- $sizeMap := index .Values.runnerSizes $size -}}
{{- if not $sizeMap -}}
{{- fail (printf "scriptRunner.size %q is not defined in .Values.runnerSizes — must be one of: small, medium, large, xlarge" $size) -}}
{{- end -}}
{{- $override := .Values.scriptRunner.resources | default dict -}}
{{- if and (kindIs "map" $override) (gt (len $override) 0) -}}
{{- toYaml $override -}}
{{- else -}}
{{- toYaml $sizeMap -}}
{{- end -}}
{{- end }}

{{/*
Fail the install when the runner would get no cloud identity at all.

AWS has never permitted this: serviceaccount.yaml marks `serviceAccount.roleArn`
required unless `aws.local.enabled` names an alternative credential source. GCP
and Azure only required their identity value *inside* the
`workloadIdentity.enabled` branch, so turning that flag off skipped the check
altogether and rendered a ServiceAccount with no annotation. The install
succeeded and the runner came up unable to reach Secret Manager, GCS, Key Vault
or Storage — which is exactly how the 2026-08-28 GKE failure happened
(DPC-55764): deployed by hand rather than through the terraform, so the operator
had no SA email to supply, and `enabled: false` was the obvious way past the
error.

Each provider keeps exactly one sanctioned way to opt out and it has to be named
explicitly, so `helm get values` always says which identity the pod is using.
*/}}
{{- define "matillion-runner.validateCloudIdentity" -}}
{{- $provider := include "matillion-runner.cloudProvider" . }}
{{- if and (eq $provider "gcp") (not .Values.gcp.workloadIdentity.enabled) (not .Values.gcp.nodeIdentity.enabled) }}
{{- fail "gcp.workloadIdentity.enabled is false, so the runner's ServiceAccount gets no iam.gke.io/gcp-service-account annotation and the pod has no GCP identity: every call to Secret Manager, GCS and the Matillion control plane's GCP-backed features fails at runtime, after a successful install. Either set gcp.workloadIdentity.serviceAccountEmail (terraform output -raw runner_workload_sa_email) and leave gcp.workloadIdentity.enabled true, or, if the pod is deliberately inheriting the GKE node pool's service account via the metadata server, set gcp.nodeIdentity.enabled=true to say so. See runner/gcp/gke/README.md, 'Identity is not optional'." }}
{{- end }}
{{- if and (eq $provider "azure") (not .Values.azure.workloadIdentity.enabled) (not .Values.azure.servicePrincipal.enabled) (not .Values.azure.nodeIdentity.enabled) }}
{{- fail "azure.workloadIdentity.enabled is false and azure.servicePrincipal.enabled is false, so the runner's ServiceAccount gets no azure.workload.identity/client-id annotation and the pod has no Azure identity: every call to Key Vault, Storage and the Matillion control plane's Azure-backed features fails at runtime, after a successful install. Either set azure.workloadIdentity.clientId and leave azure.workloadIdentity.enabled true, or enable azure.servicePrincipal, or, if the pod is deliberately inheriting the AKS node pool's kubelet managed identity via IMDS, set azure.nodeIdentity.enabled=true to say so. See runner/helm/README.md, 'Cloud Provider Specific'." }}
{{- end }}
{{- end }}

{{/*
The metrics endpoint the prometheus.io/* annotations advertise, as YAML
(port, path). The annotations can only name one endpoint, so this fails rather
than advertise an endpoint the chart isn't exposing.
*/}}
{{- define "matillion-runner.metrics.annotated" -}}
{{- $target := .Values.metrics.annotationTarget | default "legacy" -}}
{{- if not (has $target (list "legacy" "otel")) -}}
{{- fail (printf "metrics.annotationTarget is %q; must be legacy or otel." $target) -}}
{{- end -}}
{{- $endpoint := index .Values.metrics $target -}}
{{- if not $endpoint.enabled -}}
{{- fail (printf "metrics.annotationTarget is %s but metrics.%s.enabled is false. Point the annotations at an endpoint the chart exposes." $target $target) -}}
{{- end -}}
port: {{ $endpoint.port }}
path: {{ $endpoint.path }}
{{- end }}

{{/*
Custom metric names the HPA scales on, as YAML (tasks, requests). The names
are the ones the prometheus chart's adapter serves: legacy rules expose the
app_* series as-is; otel rules expose the matillion_agent_*_unit series under
the names below.
*/}}
{{- define "matillion-runner.hpa.metrics" -}}
{{- $source := .Values.hpa.metricSource | default "legacy" -}}
{{- if eq $source "legacy" -}}
{{- if not .Values.metrics.legacy.enabled -}}
{{- fail "hpa.metricSource is legacy but metrics.legacy.enabled is false, so Prometheus can no longer scrape the metrics the HPA reads. Set hpa.metricSource=otel." -}}
{{- end -}}
tasks: app_active_task_count
requests: app_active_request_count
{{- else if eq $source "otel" -}}
{{- if not .Values.metrics.otel.enabled -}}
{{- fail "hpa.metricSource is otel but metrics.otel.enabled is false. The HPA would have no metric to read." -}}
{{- end -}}
tasks: matillion_agent_task_running
requests: matillion_agent_request_active
{{- else -}}
{{- fail (printf "hpa.metricSource is %q; must be legacy or otel." $source) -}}
{{- end -}}
{{- end }}
