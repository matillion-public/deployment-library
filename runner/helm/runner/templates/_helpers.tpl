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
Create the name of the service account to use
*/}}
{{- define "matillion-runner.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "matillion-runner.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
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
