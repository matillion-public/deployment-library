{{/*
Expand the name of the chart.
*/}}
{{- define "prometheus.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "prometheus.fullname" -}}
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
{{- define "prometheus.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "prometheus.labels" -}}
helm.sh/chart: {{ include "prometheus.chart" . }}
{{ include "prometheus.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "prometheus.selectorLabels" -}}
app.kubernetes.io/name: {{ include "prometheus.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
The Prometheus server config.

An explicit config.prometheusYml wins outright — that key used to hold the whole
file, so anyone overriding it must keep getting exactly what they asked for
rather than a version this template has quietly recomposed. Only when it is
empty is the config built from config.scrapeNamespaces and
config.scrapePodLabelRegex.
*/}}
{{- define "prometheus.prometheusYml" -}}
{{- if .Values.config.prometheusYml -}}
{{- .Values.config.prometheusYml -}}
{{- else -}}
global:
  scrape_interval: 5s
scrape_configs:
  - job_name: 'matillion-runner'
    kubernetes_sd_configs:
      - role: pod
{{- with .Values.config.scrapeNamespaces }}
        namespaces:
          names:
{{- range . }}
            - {{ . }}
{{- end }}
{{- end }}
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        action: keep
        regex: {{ .Values.config.scrapePodLabelRegex }}
      - source_labels: [__meta_kubernetes_pod_ip]
        target_label: __address__
        replacement: $1:8080
      - source_labels: [__address__]
        target_label: __param_target
      - target_label: __scheme__
        replacement: http
      - target_label: __metrics_path__
        replacement: /actuator/prometheus
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
      - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
        target_label: name
      - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_instance]
        target_label: instance
      - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_component]
        target_label: component
{{- end -}}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "prometheus.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "prometheus.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
