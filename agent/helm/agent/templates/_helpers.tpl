{{/*
Expand the name of the chart.
*/}}
{{- define "matillion-agent.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "matillion-agent.fullname" -}}
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
{{- define "matillion-agent.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "matillion-agent.labels" -}}
helm.sh/chart: {{ include "matillion-agent.chart" . }}
{{ include "matillion-agent.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "matillion-agent.selectorLabels" -}}
app.kubernetes.io/name: {{ include "matillion-agent.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "matillion-agent.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "matillion-agent.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Normalize cloudProvider to lowercase for consistent comparisons
*/}}
{{- define "matillion-agent.cloudProvider" -}}
{{- .Values.cloudProvider | lower }}
{{- end }}

{{/*
Resolve the container resources block.

Precedence:
  1. .Values.dpcAgent.dpcAgent.resources, if non-empty (full override)
  2. .Values.agentSizes[.Values.agentSize] from the size map

agentSize must be one of: small, medium, large, xlarge.
*/}}
{{- define "matillion-agent.resources" -}}
{{- $size := .Values.agentSize | default "small" -}}
{{- $sizeMap := index .Values.agentSizes $size -}}
{{- if not $sizeMap -}}
{{- fail (printf "agentSize %q is not defined in .Values.agentSizes — must be one of: small, medium, large, xlarge" $size) -}}
{{- end -}}
{{- $override := .Values.dpcAgent.dpcAgent.resources | default dict -}}
{{- if and (kindIs "map" $override) (gt (len $override) 0) -}}
{{- toYaml $override -}}
{{- else -}}
{{- toYaml $sizeMap -}}
{{- end -}}
{{- end }}
