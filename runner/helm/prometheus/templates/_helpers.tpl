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
{{- if .Values.config.legacy.enabled }}
{{- include "prometheus.runnerScrapeJob" (dict "root" . "job" "matillion-runner" "port" .Values.config.legacy.port "path" .Values.config.legacy.path) }}
{{- end }}
{{- if .Values.config.otel.enabled }}
{{- include "prometheus.runnerScrapeJob" (dict "root" . "job" "matillion-runner-otel" "port" .Values.config.otel.port "path" .Values.config.otel.path) }}
{{- if or .Values.config.otel.dropTargetInfo .Values.config.otel.keepMetricsRegex }}
    metric_relabel_configs:
{{- end }}
{{- if .Values.config.otel.dropTargetInfo }}
      # target_info carries the runner's resource attributes, including the full
      # JVM command line, which can hold credentials passed on it. Not needed
      # for scaling or dashboards, so it isn't stored.
      - source_labels: [__name__]
        regex: target_info
        action: drop
{{- end }}
{{- with .Values.config.otel.keepMetricsRegex }}
      - source_labels: [__name__]
        regex: {{ . | quote }}
        action: keep
{{- end }}
{{- end }}
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


{{/*
One runner scrape job. Both endpoints are discovered the same way (the
namespaces and pod label regex in config.*) and differ only in port and path,
so the jobs are rendered from this single definition rather than kept in sync
by hand. Called with a dict: root (the chart context), job, port, path.
*/}}
{{- define "prometheus.runnerScrapeJob" }}
  - job_name: {{ .job | squote }}
    kubernetes_sd_configs:
      - role: pod
{{- with .root.Values.config.scrapeNamespaces }}
        namespaces:
          names:
{{- range . }}
            - {{ . }}
{{- end }}
{{- end }}
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        action: keep
        regex: {{ .root.Values.config.scrapePodLabelRegex }}
      - source_labels: [__meta_kubernetes_pod_ip]
        target_label: __address__
        replacement: $1:{{ .port }}
      - source_labels: [__address__]
        target_label: __param_target
      - target_label: __scheme__
        replacement: http
      - target_label: __metrics_path__
        replacement: {{ .path }}
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
{{- end }}

{{/*
Runner ports the egress policy opens: one per scraped endpoint. Falls back to
the legacy port when neither job is rendered (prometheusYml override, or both
disabled), so the policy never ends up with an empty port list, which would
admit every port.
*/}}
{{- define "prometheus.runnerScrapePorts" -}}
{{- $ports := list -}}
{{- if and (not .Values.config.prometheusYml) .Values.config.legacy.enabled -}}
{{- $ports = append $ports .Values.config.legacy.port -}}
{{- end -}}
{{- if and (not .Values.config.prometheusYml) .Values.config.otel.enabled -}}
{{- $ports = append $ports .Values.config.otel.port -}}
{{- end -}}
{{- if or .Values.config.prometheusYml (not $ports) -}}
{{- $ports = list .Values.config.legacy.port .Values.config.otel.port -}}
{{- end -}}
{{- range $ports }}
- protocol: TCP
  port: {{ . }}
{{- end }}
{{- end }}
