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
