"""Script runner autoscaling and graceful scale-in (DPC-55687).

The runner chart and the prometheus chart each hold half of the wiring: the
script runner pod exposes script_runner_active_sessions (DPC-55686), the
prometheus chart scrapes it and its adapter serves it, and the runner chart's
HPA scales on it. Each half renders fine on its own, so the failure mode is the
two drifting apart — an HPA that sits at minReplicas with nothing to explain
why. The TestChartsAgree class pins the joins.
"""
import os
import re
import subprocess

import pytest
import yaml

RUNNER_CHART = 'runner/helm/runner'
PROMETHEUS_CHART = 'runner/helm/prometheus'
# The release name the prometheus chart's defaults assume.
RELEASE = 'matillion-runner'
SCRIPT_RUNNER = [
    'scriptRunner.enabled=true',
    'scriptRunner.authorizedKeys=ssh-ed25519 AAAATESTKEY agent@matillion',
    'scriptRunner.privateKey=PRIVATE-KEY-MATERIAL',
    'scriptRunner.image.repository=public.ecr.aws/matillion/maia-script-runner',
    'scriptRunner.serviceAccount.roleArn=arn:aws:iam::123456789012:role/runner',
]
HPA = ['scriptRunner.hpa.enabled=true', 'scriptRunner.hpa.targetSessionsPerPod=8']


def helm(chart, *sets, release=RELEASE, values=()):
    args = []
    for v in values:
        args += ['-f', v]
    for s in sets:
        args += ['--set', s]
    return subprocess.run(['helm', 'template', release, chart, *args],
                          capture_output=True, text=True)


def runner_docs(*sets):
    result = helm(RUNNER_CHART, *SCRIPT_RUNNER, *sets,
                  values=['tests/values/test-values.yaml'])
    assert result.returncode == 0, result.stderr
    return [d for d in yaml.safe_load_all(result.stdout) if d]


def prometheus_docs(*sets):
    result = helm(PROMETHEUS_CHART, *sets, release='p')
    assert result.returncode == 0, result.stderr
    return [d for d in yaml.safe_load_all(result.stdout) if d]


def script_runner(documents, kind):
    return next(d for d in documents if d['kind'] == kind
                and 'script-runner' in d['metadata']['name'])


def pod(documents):
    return script_runner(documents, 'Deployment')['spec']['template']


def container(documents):
    return pod(documents)['spec']['containers'][0]


def env(documents):
    return {e['name']: e.get('value') for e in container(documents)['env']}


def scrape_job(*sets):
    cm = next(d for d in prometheus_docs(*sets)
              if d['kind'] == 'ConfigMap' and 'prometheus.yml' in d.get('data', {}))
    jobs = yaml.safe_load(cm['data']['prometheus.yml'])['scrape_configs']
    return next(j for j in jobs if j['job_name'] == 'matillion-script-runner')


def relabel(job):
    return {r.get('target_label'): r.get('replacement') for r in job['relabel_configs']}


def prometheus_egress(*sets):
    policy = next(d for d in prometheus_docs(*sets) if d['kind'] == 'NetworkPolicy'
                  and not d['metadata']['name'].endswith('-adapter'))
    return policy['spec']['egress']


class TestMetricsEndpoint:
    def test_exposed_by_default(self):
        documents = runner_docs()
        assert {'containerPort': 9100, 'name': 'metrics'} in container(documents)['ports']
        assert env(documents)['RUNNER_METRICS_ENABLED'] == 'true'
        assert env(documents)['RUNNER_METRICS_PORT'] == '9100'

    def test_annotations_for_annotation_based_scrapers(self):
        annotations = pod(runner_docs())['metadata']['annotations']
        assert annotations['prometheus.io/scrape'] == 'true'
        assert annotations['prometheus.io/port'] == '9100'
        assert annotations['prometheus.io/path'] == '/metrics'

    def test_custom_port_reaches_the_image(self):
        """The image binds RUNNER_METRICS_PORT, so the chart can't open one port
        while the exporter listens on another."""
        documents = runner_docs('scriptRunner.metrics.port=9555')
        assert {'containerPort': 9555, 'name': 'metrics'} in container(documents)['ports']
        assert env(documents)['RUNNER_METRICS_PORT'] == '9555'

    def test_disabled(self):
        documents = runner_docs('scriptRunner.metrics.enabled=false')
        assert [p['name'] for p in container(documents)['ports']] == ['ssh']
        assert 'annotations' not in pod(documents)['metadata']
        assert env(documents)['RUNNER_METRICS_ENABLED'] == 'false'
        ingress = script_runner(documents, 'NetworkPolicy')['spec']['ingress']
        assert [p['port'] for r in ingress for p in r['ports']] == [2222]

    def test_netpol_admits_prometheus_on_the_metrics_port_only(self):
        ingress = script_runner(runner_docs(), 'NetworkPolicy')['spec']['ingress']
        metrics = [r for r in ingress if r['ports'] == [{'protocol': 'TCP', 'port': 9100}]]
        assert len(metrics) == 1
        assert metrics[0]['from'] == [
            {'namespaceSelector': {'matchLabels': {'name': 'monitoring'}}},
            {'namespaceSelector': {'matchLabels': {'kubernetes.io/metadata.name': 'monitoring'}}},
            {'podSelector': {'matchLabels': {'app': 'prometheus'}}},
        ]

    def test_netpol_follows_the_prometheus_namespace(self):
        """EKS installs Prometheus into `prometheus`, GKE's docs into `monitoring`.
        Nobody labels those namespaces `name:`, so the built-in label is matched too."""
        ingress = script_runner(runner_docs('networkPolicy.prometheusNamespace=prometheus'),
                                'NetworkPolicy')['spec']['ingress']
        assert {'namespaceSelector': {'matchLabels': {'kubernetes.io/metadata.name': 'prometheus'}}
                } in ingress[1]['from']

    def test_azure_annotations_kept_alongside(self):
        documents = runner_docs('cloudProvider=azure',
                                'azure.workloadIdentity.enabled=true',
                                'azure.workloadIdentity.clientId=agent',
                                'scriptRunner.serviceAccount.clientId=runner')
        annotations = pod(documents)['metadata']['annotations']
        assert annotations['azure.workload.identity/inject-proxy-sidecar'] == 'true'
        assert annotations['prometheus.io/port'] == '9100'


    @pytest.mark.parametrize('port', [80, 1023, 2222, 65536])
    def test_port_the_image_refuses_fails_the_render(self, port):
        result = helm(RUNNER_CHART, *SCRIPT_RUNNER, f'scriptRunner.metrics.port={port}',
                      values=['tests/values/test-values.yaml'])
        assert result.returncode != 0
        assert 'must be 1024-65535 and not 2222' in result.stderr

    def test_port_not_checked_when_disabled(self):
        runner_docs('scriptRunner.metrics.enabled=false', 'scriptRunner.metrics.port=80')


class TestReadiness:
    def test_not_ready_until_sshd_listens(self):
        """New HPA pods take no connections while the entry point is still
        hydrating; a draining pod drops out of the Service once its listener closes."""
        probe = container(runner_docs())['readinessProbe']
        assert probe['tcpSocket'] == {'port': 'ssh'}

    def test_liveness_timings_unchanged(self):
        probe = container(runner_docs())['livenessProbe']
        assert (probe['initialDelaySeconds'], probe['periodSeconds'],
                probe['timeoutSeconds'], probe['failureThreshold']) == (10, 30, 5, 3)


class TestGracefulScaleIn:
    def test_grace_period_defaults_to_the_container_apps_value(self):
        assert pod(runner_docs())['spec']['terminationGracePeriodSeconds'] == 600

    def test_grace_period_configurable(self):
        documents = runner_docs('scriptRunner.terminationGracePeriodSeconds=3600')
        assert pod(documents)['spec']['terminationGracePeriodSeconds'] == 3600

    def test_no_prestop_hook(self):
        """The image drains on SIGTERM itself; a preStop sleep would only delay
        the drain and eat into the grace period."""
        assert 'preStop' not in (container(runner_docs()).get('lifecycle') or {})


class TestHpa:
    def test_off_by_default(self):
        documents = runner_docs()
        assert not any(d['kind'] == 'HorizontalPodAutoscaler'
                       and 'script-runner' in d['metadata']['name'] for d in documents)
        assert script_runner(documents, 'Deployment')['spec']['replicas'] == 2

    def test_targets_the_script_runner_on_sessions(self):
        documents = runner_docs(*HPA)
        hpa = script_runner(documents, 'HorizontalPodAutoscaler')
        assert hpa['spec']['scaleTargetRef'] == {
            'apiVersion': 'apps/v1', 'kind': 'Deployment',
            'name': script_runner(documents, 'Deployment')['metadata']['name']}
        assert hpa['spec']['metrics'] == [{
            'type': 'Pods',
            'pods': {'metric': {'name': 'script_runner_active_sessions'},
                     'target': {'type': 'AverageValue', 'averageValue': '8'}}}]
        assert (hpa['spec']['minReplicas'], hpa['spec']['maxReplicas']) == (2, 5)

    def test_deployment_leaves_replicas_to_the_hpa(self):
        """Otherwise every helm upgrade resets the count the HPA scaled to."""
        assert 'replicas' not in script_runner(runner_docs(*HPA), 'Deployment')['spec']

    def test_agent_hpa_unchanged(self):
        def agent_hpa(documents):
            return next(d for d in documents if d['kind'] == 'HorizontalPodAutoscaler'
                        and 'script-runner' not in d['metadata']['name'])
        assert agent_hpa(runner_docs(*HPA)) == agent_hpa(runner_docs())

    def test_scale_down_is_gradual(self):
        behavior = script_runner(runner_docs(*HPA), 'HorizontalPodAutoscaler')['spec']['behavior']
        assert behavior['scaleDown']['stabilizationWindowSeconds'] == 300
        assert behavior['scaleDown']['policies'] == [
            {'type': 'Pods', 'value': 1, 'periodSeconds': 60}]

    def test_target_is_required(self):
        result = helm(RUNNER_CHART, *SCRIPT_RUNNER, 'scriptRunner.hpa.enabled=true',
                      values=['tests/values/test-values.yaml'])
        assert result.returncode != 0
        assert 'scriptRunner.hpa.targetSessionsPerPod is required' in result.stderr

    @pytest.mark.parametrize('target', ['0', '-1'])
    def test_target_must_be_positive(self, target):
        result = helm(RUNNER_CHART, *SCRIPT_RUNNER, 'scriptRunner.hpa.enabled=true',
                      f'scriptRunner.hpa.targetSessionsPerPod={target}',
                      values=['tests/values/test-values.yaml'])
        assert result.returncode != 0
        assert 'must be above 0' in result.stderr

    def test_needs_the_metric(self):
        result = helm(RUNNER_CHART, *SCRIPT_RUNNER, *HPA, 'scriptRunner.metrics.enabled=false',
                      values=['tests/values/test-values.yaml'])
        assert result.returncode != 0
        assert 'needs scriptRunner.metrics.enabled' in result.stderr

    def test_not_rendered_without_the_script_runner(self):
        result = helm(RUNNER_CHART, *HPA, values=['tests/values/test-values.yaml'])
        assert result.returncode == 0, result.stderr
        assert 'script-runner' not in result.stdout

    @pytest.mark.parametrize('cloud, sets', [
        ('aws', []),
        ('azure', ['azure.workloadIdentity.enabled=true', 'azure.workloadIdentity.clientId=a',
                   'scriptRunner.serviceAccount.clientId=r']),
        ('gcp', ['gcp.workloadIdentity.enabled=true',
                 'gcp.workloadIdentity.serviceAccountEmail=a@p.iam.gserviceaccount.com',
                 'scriptRunner.serviceAccount.serviceAccountEmail=r@p.iam.gserviceaccount.com']),
    ])
    def test_renders_on_every_cloud(self, cloud, sets):
        documents = runner_docs(f'cloudProvider={cloud}', *sets, *HPA)
        assert script_runner(documents, 'HorizontalPodAutoscaler')
        assert pod(documents)['spec']['terminationGracePeriodSeconds'] == 600


class TestPrometheus:
    def test_scrape_job(self):
        job = scrape_job()
        assert relabel(job)['__address__'] == '$1:9100'
        assert relabel(job)['__metrics_path__'] == '/metrics'

    def test_shares_namespace_discovery_with_the_runner_jobs(self):
        job = scrape_job('config.scrapeNamespaces={bu-grid,bu-retail}')
        assert job['kubernetes_sd_configs'][0]['namespaces']['names'] == ['bu-grid', 'bu-retail']

    def test_own_pod_label(self):
        """The runner jobs' regex must not change: it selects agent pods."""
        job = scrape_job('config.scriptRunner.podLabelRegex=.*script-runner-pods')
        assert job['relabel_configs'][0]['regex'] == '.*script-runner-pods'

    def test_can_be_turned_off(self):
        documents = prometheus_docs('config.scriptRunner.enabled=false')
        text = yaml.safe_dump_all(documents)
        assert 'matillion-script-runner' not in text
        assert all(9100 not in [p['port'] for p in r['ports']]
                   for r in prometheus_egress('config.scriptRunner.enabled=false'))

    def test_egress_to_script_runner_pods(self):
        rule = prometheus_egress()[1]
        assert rule['to'] == [{'podSelector': {'matchLabels': {
            'app': 'matillion-runner-script-runner-pods'}}}]
        assert rule['ports'] == [{'protocol': 'TCP', 'port': 9100}]

    def test_egress_follows_the_pod_selector_setting(self):
        rule = prometheus_egress('networkPolicy.scriptRunnerPodSelector.app=acme-matillion-runner-script-runner-pods')[1]
        assert rule['to'] == [{'podSelector': {'matchLabels': {
            'app': 'acme-matillion-runner-script-runner-pods'}}}]

    def test_no_egress_without_the_job(self):
        """A raw prometheusYml has no matillion-script-runner job to open 9100 for."""
        egress = prometheus_egress('config.prometheusYml=scrape_configs: []',
                                   'networkPolicy.additionalScrapeNamespaces={bu2}')
        assert all(p['port'] != 9100 for r in egress for p in r['ports'])

    def test_egress_into_additional_namespaces(self):
        egress = prometheus_egress('networkPolicy.additionalScrapeNamespaces={bu2}')
        script = [r for r in egress if r['ports'] == [{'protocol': 'TCP', 'port': 9100}]]
        assert {'namespaceSelector': {'matchLabels': {'kubernetes.io/metadata.name': 'bu2'}},
                'podSelector': {'matchLabels': {'app': 'matillion-runner-script-runner-pods'}}
                } in [r['to'][0] for r in script]


class TestChartsAgree:
    """Defaults on both sides must line up for the default release name."""

    def test_scrape_regex_matches_the_pod_label(self):
        label = pod(runner_docs())['metadata']['labels']['app']
        assert label == scrape_job()['relabel_configs'][0]['regex']

    def test_egress_selector_matches_the_pod_label(self):
        label = pod(runner_docs())['metadata']['labels']['app']
        assert prometheus_egress()[1]['to'][0]['podSelector']['matchLabels']['app'] == label

    def test_scraped_port_is_the_exposed_port(self):
        exposed = next(p['containerPort'] for p in container(runner_docs())['ports']
                       if p['name'] == 'metrics')
        assert relabel(scrape_job())['__address__'] == f'$1:{exposed}'

    def test_adapter_serves_the_hpa_metric(self):
        cm = next(d for d in prometheus_docs()
                  if d['kind'] == 'ConfigMap' and 'config.yaml' in d.get('data', {}))
        served = [r['name']['as'] for r in yaml.safe_load(cm['data']['config.yaml'])['rules']]
        hpa = script_runner(runner_docs(*HPA), 'HorizontalPodAutoscaler')
        assert hpa['spec']['metrics'][0]['pods']['metric']['name'] in served


class TestSizingDefaults:
    """DPC-55688: the documented path is the default path."""

    def test_two_replicas_by_default(self):
        assert script_runner(runner_docs(), 'Deployment')['spec']['replicas'] == 2

    def test_single_replica_still_possible(self):
        documents = runner_docs('scriptRunner.replicas=1')
        assert script_runner(documents, 'Deployment')['spec']['replicas'] == 1

    def test_zero_is_zero(self):
        """`| default` used to turn an explicit 0 into a running pod."""
        documents = runner_docs('scriptRunner.replicas=0')
        assert script_runner(documents, 'Deployment')['spec']['replicas'] == 0

    def test_prefers_one_pod_per_node(self):
        spread = pod(runner_docs())['spec']['topologySpreadConstraints']
        assert spread == [{
            'maxSkew': 1, 'topologyKey': 'kubernetes.io/hostname',
            'whenUnsatisfiable': 'ScheduleAnyway',
            'labelSelector': {'matchLabels': {
                'app': pod(runner_docs())['metadata']['labels']['app']}}}]

    def test_zone_spread_follows_the_runner_setting(self):
        spread = pod(runner_docs('topologySpread.enabled=true'))['spec']['topologySpreadConstraints']
        assert [c['topologyKey'] for c in spread] == [
            'kubernetes.io/hostname', 'topology.kubernetes.io/zone']
        assert all(c['whenUnsatisfiable'] == 'ScheduleAnyway' for c in spread)

    def test_pdb_follows_the_runner_setting(self):
        assert not any(d['kind'] == 'PodDisruptionBudget' and 'script-runner' in d['metadata']['name']
                       for d in runner_docs())
        pdb = script_runner(runner_docs('podDisruptionBudget.enabled=true',
                                        'hpa.minReplicas=2'), 'PodDisruptionBudget')
        assert pdb['spec']['maxUnavailable'] == 1
        assert pdb['spec']['selector']['matchLabels']['app'] == \
            pod(runner_docs())['metadata']['labels']['app']

    @pytest.mark.parametrize('sets', [
        ['scriptRunner.replicas=1'],
        [*HPA, 'scriptRunner.hpa.minReplicas=1'],
    ])
    def test_pdb_refuses_a_single_replica_floor(self, sets):
        result = helm(RUNNER_CHART, *SCRIPT_RUNNER, 'podDisruptionBudget.enabled=true',
                      'hpa.minReplicas=2', *[f'{s}' for s in sets],
                      values=['tests/values/test-values.yaml'])
        assert result.returncode != 0
        assert "script runner's replica floor is 1" in result.stderr


class TestSizingDocs:
    """The sizing guide and the per-cloud sections link to each other (DPC-55688).
    Links are resolved relative to the file and checked for a matching heading,
    not matched as substrings: `../helm/x` is a substring of the broken
    `../../helm/x`."""

    GUIDE = 'runner/helm/README.md'
    CLOUDS = ['runner/aws/eks/README.md', 'runner/azure/README.md',
              'runner/gcp/gke/README.md']

    @staticmethod
    def anchors(path):
        """GitHub-style heading anchors in a markdown file."""
        out = set()
        for line in open(path):
            m = re.match(r'#+\s+(.*)', line)
            if m:
                slug = re.sub(r'[^\w\- ]', '', m.group(1).strip().lower())
                out.add(slug.replace(' ', '-'))
        return out

    @classmethod
    def assert_link(cls, source, href):
        target, _, anchor = href.partition('#')
        path = os.path.normpath(os.path.join(os.path.dirname(source), target))
        assert os.path.isfile(path), f'{source}: {href} -> {path} does not exist'
        assert anchor in cls.anchors(path), f'{source}: #{anchor} not a heading in {path}'

    @staticmethod
    def links(source, fragment):
        return re.findall(r'\]\(([^)]*#' + re.escape(fragment) + r')\)', open(source).read())

    @pytest.mark.parametrize('readme', CLOUDS)
    def test_each_cloud_links_to_the_guide(self, readme):
        assert 'script-runner-sizing-and-scaling' in self.anchors(readme)
        found = self.links(readme, 'sizing-the-script-runner')
        assert found, f'{readme} has no link to the sizing guide'
        for href in found:
            self.assert_link(readme, href)

    def test_guide_links_back_to_each_cloud(self):
        found = self.links(self.GUIDE, 'script-runner-sizing-and-scaling')
        assert len(found) == len(self.CLOUDS)
        for href in found:
            self.assert_link(self.GUIDE, href)
