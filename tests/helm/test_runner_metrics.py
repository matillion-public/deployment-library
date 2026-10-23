"""Runner chart: dual metrics endpoints and HPA metric source (DPC-58190).

The runner serves the deprecated Micrometer endpoint (:8080/actuator/prometheus)
and the OpenTelemetry exporter (:9464/metrics) side by side until cutover. These
pin what the chart exposes for each combination, and that the defaults leave
existing scrapers and HPAs on the legacy names.
"""
import subprocess

import pytest
import yaml

RUNNER_CHART = 'runner/helm/runner'
BASE = ['-f', 'tests/values/test-values.yaml']


def render(*sets):
    args = []
    for s in sets:
        args += ['--set', s]
    result = subprocess.run(['helm', 'template', 't', RUNNER_CHART, *BASE, *args],
                            capture_output=True, text=True)
    return result


def docs(*sets):
    result = render(*sets)
    assert result.returncode == 0, result.stderr
    return [d for d in yaml.safe_load_all(result.stdout) if d]


def runner(documents):
    deployment = next(d for d in documents if d['kind'] == 'Deployment'
                      and 'script-runner' not in d['metadata']['name'])
    return deployment['spec']['template']


def container(documents):
    return runner(documents)['spec']['containers'][0]


def annotations(documents):
    return runner(documents)['metadata'].get('annotations') or {}


def prometheus_ingress_ports(documents):
    policy = next(d for d in documents if d['kind'] == 'NetworkPolicy'
                  and d['metadata']['name'].endswith('-netpol'))
    return [[p['port'] for p in rule.get('ports', [])]
            for rule in policy['spec'].get('ingress') or []]


def hpa_metric_names(documents):
    hpa = next(d for d in documents if d['kind'] == 'HorizontalPodAutoscaler')
    return [m['pods']['metric']['name'] for m in hpa['spec']['metrics']]


def env(documents):
    return {e['name']: e.get('value') for e in container(documents).get('env', [])}


class TestDefaults:
    """Both endpoints exposed; everything that reads metrics stays on legacy."""

    def test_both_ports_declared(self):
        ports = {p['name']: p['containerPort'] for p in container(docs())['ports']}
        assert ports == {'metrics': 8080, 'otel-metrics': 9464}

    def test_annotations_still_advertise_legacy(self):
        a = annotations(docs())
        assert a['prometheus.io/port'] == '8080'
        assert a['prometheus.io/path'] == '/actuator/prometheus'
        assert a['prometheus.io/scrape'] == 'true'

    def test_prometheus_may_reach_both_ports(self):
        assert prometheus_ingress_ports(docs()) == [[8080, 9464]]

    def test_hpa_stays_on_legacy_names(self):
        assert hpa_metric_names(docs()) == ['app_active_task_count', 'app_active_request_count']

    def test_exporter_port_passed_to_runner(self):
        assert env(docs())['OTEL_EXPORTER_PROMETHEUS_PORT'] == '9464'


class TestOtelEndpoint:
    def test_annotations_can_target_otel(self):
        a = annotations(docs('metrics.annotationTarget=otel'))
        assert (a['prometheus.io/port'], a['prometheus.io/path']) == ('9464', '/metrics')

    def test_custom_port_flows_everywhere(self):
        """The port the exporter binds, the port declared and the port the policy
        opens all come from one value, so they can't drift apart."""
        d = docs('metrics.otel.port=9555', 'metrics.annotationTarget=otel')
        assert env(d)['OTEL_EXPORTER_PROMETHEUS_PORT'] == '9555'
        assert 9555 in [p['containerPort'] for p in container(d)['ports']]
        assert prometheus_ingress_ports(d) == [[8080, 9555]]
        assert annotations(d)['prometheus.io/port'] == '9555'

    def test_disabling_removes_port_env_and_ingress(self):
        d = docs('metrics.otel.enabled=false')
        assert [p['containerPort'] for p in container(d)['ports']] == [8080]
        assert 'OTEL_EXPORTER_PROMETHEUS_PORT' not in env(d)
        assert prometheus_ingress_ports(d) == [[8080]]


class TestLegacyEndpoint:
    def test_disabling_closes_its_ingress_but_keeps_the_health_port(self):
        """8080 also serves the probes, so it stays declared; only Prometheus's
        access to it is withdrawn."""
        d = docs('metrics.legacy.enabled=false', 'metrics.annotationTarget=otel',
                 'hpa.metricSource=otel')
        assert 8080 in [p['containerPort'] for p in container(d)['ports']]
        assert prometheus_ingress_ports(d) == [[9464]]

    def test_neither_endpoint_means_no_scrape_rule_at_all(self):
        """A rule with an empty port list would admit every port, so the rule
        must go rather than render empty."""
        d = docs('metrics.legacy.enabled=false', 'metrics.otel.enabled=false',
                 'hpa.enabled=false')
        assert prometheus_ingress_ports(d) == []
        assert 'prometheus.io/scrape' not in annotations(d)


class TestHpaMetricSource:
    def test_otel_source_uses_adapter_names(self):
        assert hpa_metric_names(docs('hpa.metricSource=otel')) == [
            'matillion_agent_task_running', 'matillion_agent_request_active']

    def test_target_is_shared_between_sources(self):
        """Both sources count the same in-flight work, so switching needs no
        retuning of the target."""
        legacy = next(d for d in docs() if d['kind'] == 'HorizontalPodAutoscaler')
        otel = next(d for d in docs('hpa.metricSource=otel')
                    if d['kind'] == 'HorizontalPodAutoscaler')
        assert [m['pods']['target'] for m in legacy['spec']['metrics']] == \
            [m['pods']['target'] for m in otel['spec']['metrics']]


class TestMisconfigurationFailsLoudly:
    """Each of these would otherwise render a runner whose HPA silently sits at
    minReplicas, or whose annotations name a port nothing can reach."""

    @pytest.mark.parametrize('sets, message', [
        (['metrics.otel.enabled=false', 'hpa.metricSource=otel'],
         'hpa.metricSource is otel but metrics.otel.enabled is false'),
        (['metrics.legacy.enabled=false', 'metrics.annotationTarget=otel'],
         'hpa.metricSource is legacy but metrics.legacy.enabled is false'),
        (['metrics.otel.enabled=false', 'metrics.annotationTarget=otel'],
         'metrics.annotationTarget is otel but metrics.otel.enabled is false'),
        (['metrics.annotationTarget=both'], 'must be legacy or otel'),
        (['hpa.metricSource=micrometer'], 'must be legacy or otel'),
    ])
    def test_rejected(self, sets, message):
        result = render(*sets)
        assert result.returncode != 0
        assert message in result.stderr
