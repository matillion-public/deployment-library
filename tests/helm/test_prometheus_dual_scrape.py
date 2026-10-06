"""Prometheus chart: scraping both runner metrics endpoints (DPC-58191).

The runner serves the deprecated Micrometer endpoint and the OpenTelemetry
exporter side by side until cutover. These pin that the chart scrapes both as
separate jobs, that the legacy job is untouched for existing dashboards and
alerts, and that the adapter serves both sets of HPA metrics at once so each
runner release can choose its source.
"""
import subprocess

import pytest
import yaml

PROMETHEUS_CHART = 'runner/helm/prometheus'


def render(*sets):
    args = []
    for s in sets:
        args += ['--set', s]
    result = subprocess.run(['helm', 'template', 'p', PROMETHEUS_CHART, *args],
                            capture_output=True, text=True, check=True)
    return [d for d in yaml.safe_load_all(result.stdout) if d]


def jobs(*sets):
    cm = next(d for d in render(*sets)
              if d['kind'] == 'ConfigMap' and 'prometheus.yml' in d.get('data', {}))
    parsed = yaml.safe_load(cm['data']['prometheus.yml'])
    return {j['job_name']: j for j in parsed.get('scrape_configs') or []}


def target(job):
    relabel = {r.get('target_label'): r.get('replacement') for r in job['relabel_configs']}
    return relabel['__address__'], relabel['__metrics_path__']


def egress_ports(*sets):
    policy = next(d for d in render(*sets) if d['kind'] == 'NetworkPolicy'
                  and not d['metadata']['name'].endswith('-adapter'))
    return [[p['port'] for p in rule.get('ports', [])] for rule in policy['spec']['egress']]


def adapter_rules():
    cm = next(d for d in render()
              if d['kind'] == 'ConfigMap' and 'config.yaml' in d.get('data', {}))
    return yaml.safe_load(cm['data']['config.yaml'])['rules']


class TestScrapeJobs:
    def test_both_jobs_by_default(self):
        j = jobs()
        assert list(j) == ['matillion-runner', 'matillion-runner-otel']
        assert target(j['matillion-runner']) == ('$1:8080', '/actuator/prometheus')
        assert target(j['matillion-runner-otel']) == ('$1:9464', '/metrics')

    def test_jobs_share_discovery(self):
        """Both endpoints live on the same pods, so a tenant scraped on one must
        be scraped on the other."""
        j = jobs('config.scrapeNamespaces={bu-grid,bu-retail}',
                 'config.scrapePodLabelRegex=.*matillion-runner-pods')
        legacy, otel = j['matillion-runner'], j['matillion-runner-otel']
        assert legacy['kubernetes_sd_configs'] == otel['kubernetes_sd_configs']
        assert legacy['relabel_configs'][0] == otel['relabel_configs'][0]
        assert otel['kubernetes_sd_configs'][0]['namespaces']['names'] == ['bu-grid', 'bu-retail']

    def test_target_info_dropped_from_otel_job(self):
        """It carries the full JVM command line, which can hold credentials."""
        relabel = jobs()['matillion-runner-otel']['metric_relabel_configs']
        assert {'source_labels': ['__name__'], 'regex': 'target_info',
                'action': 'drop'} in relabel
        assert 'metric_relabel_configs' not in jobs()['matillion-runner']

    def test_target_info_can_be_kept(self):
        assert 'metric_relabel_configs' not in jobs('config.otel.dropTargetInfo=false')[
            'matillion-runner-otel']

    def test_keep_regex_narrows_otel_job(self):
        relabel = jobs('config.otel.keepMetricsRegex=matillion_agent_.*')[
            'matillion-runner-otel']['metric_relabel_configs']
        assert relabel[-1] == {'source_labels': ['__name__'],
                               'regex': 'matillion_agent_.*', 'action': 'keep'}

    @pytest.mark.parametrize('disabled, remaining', [
        ('config.otel.enabled=false', ['matillion-runner']),
        ('config.legacy.enabled=false', ['matillion-runner-otel']),
    ])
    def test_each_job_can_be_turned_off(self, disabled, remaining):
        assert list(jobs(disabled)) == remaining

    def test_custom_otel_port(self):
        assert target(jobs('config.otel.port=9555')['matillion-runner-otel'])[0] == '$1:9555'
        assert egress_ports('config.otel.port=9555')[0] == [8080, 9555]


class TestEgressPolicy:
    def test_both_ports_opened(self):
        assert egress_ports()[0] == [8080, 9464]

    @pytest.mark.parametrize('disabled, ports', [
        ('config.otel.enabled=false', [8080]),
        ('config.legacy.enabled=false', [9464]),
    ])
    def test_only_scraped_ports_opened(self, disabled, ports):
        assert egress_ports(disabled)[0] == ports

    def test_never_an_empty_port_list(self):
        """An empty port list admits every port. With neither job composed
        (both off, or a raw prometheusYml), fall back to both runner ports."""
        assert egress_ports('config.legacy.enabled=false',
                            'config.otel.enabled=false')[0] == [8080, 9464]
        assert egress_ports('config.prometheusYml=scrape_configs: []')[0] == [8080, 9464]


class TestAdapterRules:
    def test_both_metric_sets_served(self):
        """Served side by side so each runner release picks via hpa.metricSource."""
        assert [r['name']['as'] for r in adapter_rules()] == [
            'app_active_task_count', 'app_active_request_count',
            'matillion_agent_task_running', 'matillion_agent_request_active']

    def test_otel_rules_read_the_exporters_unit_suffixed_series(self):
        """Names confirmed against a DPC-55707 runner image on EKS and AKS."""
        otel = {r['name']['as']: r for r in adapter_rules()
                if r['name']['as'].startswith('matillion_agent_')}
        assert otel['matillion_agent_task_running']['seriesQuery'].startswith(
            'matillion_agent_task_running_unit{')
        assert otel['matillion_agent_request_active']['seriesQuery'].startswith(
            'matillion_agent_request_active_unit{')

    def test_otel_rules_map_pods_like_the_legacy_ones(self):
        rules = adapter_rules()
        assert all(r['resources'] == rules[0]['resources'] for r in rules)
        assert all(r['metricsQuery'] == rules[0]['metricsQuery'] for r in rules)
