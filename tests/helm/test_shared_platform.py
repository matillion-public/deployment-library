#!/usr/bin/env python3
"""Shared multi-tenant runner platform — DPC-53846.

Every extension in this epic is values-gated with a default that reproduces the
previous rendered output, so most of these tests are paired: one asserting the
feature is absent by default, one asserting it behaves correctly when enabled.
"""
import os
import subprocess
import tempfile

import pytest
import yaml

RUNNER_CHART = 'runner/helm/runner'
PROMETHEUS_CHART = 'runner/helm/prometheus'


def render(values, chart_path=RUNNER_CHART, release='test-release'):
    """Render a chart and return its non-empty documents."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
        yaml.dump(values, f)
        values_file = f.name

    try:
        result = subprocess.run(
            ['helm', 'template', release, chart_path, '-f', values_file],
            capture_output=True, text=True, check=True,
        )
        return [doc for doc in yaml.safe_load_all(result.stdout) if doc is not None]
    finally:
        os.unlink(values_file)


def render_failure(values, chart_path=RUNNER_CHART):
    """Render expecting failure, returning stderr.

    Several guard rails here are deliberate `fail` calls rather than silent
    no-ops — a configuration that quietly does nothing is the failure mode they
    exist to prevent — so the error text is the behaviour under test.
    """
    with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
        yaml.dump(values, f)
        values_file = f.name

    try:
        result = subprocess.run(
            ['helm', 'template', 'test-release', chart_path, '-f', values_file],
            capture_output=True, text=True,
        )
        assert result.returncode != 0, (
            f'expected render to fail, but it succeeded:\n{result.stdout[:2000]}'
        )
        return result.stderr
    finally:
        os.unlink(values_file)


def find_kind(documents, kind, name_suffix=None):
    for doc in documents:
        if doc.get('kind') != kind:
            continue
        if name_suffix is None or doc.get('metadata', {}).get('name', '').endswith(name_suffix):
            return doc
    return None


@pytest.fixture
def base_values():
    return {
        'cloudProvider': 'aws',
        'config': {
            'oauthClientId': 'test-client-id',
            'oauthClientSecret': 'test-client-secret',
        },
        'serviceAccount': {'roleArn': 'arn:aws:iam::123456789012:role/test-role'},
        'dpcAgent': {
            'dpcAgent': {
                'env': {
                    'accountId': '12345',
                    'agentId': 'test-agent-id',
                    'matillionRegion': 'us1',
                },
                'image': {'repository': 'nginx', 'tag': 'latest'},
            }
        },
        'hpa': {'maxReplicas': 10, 'metrics': {'target': {'averageValue': '50'}}},
    }


def pod_spec(values):
    deployment = find_kind(render(values), 'Deployment')
    assert deployment is not None, 'Deployment not rendered'
    return deployment['spec']['template']['spec']


class TestZoneResilience:
    """AZ spread, affinity and PodDisruptionBudget — item 1."""

    def test_topology_spread_absent_by_default(self, base_values):
        assert 'topologySpreadConstraints' not in pod_spec(base_values)

    def test_affinity_absent_by_default(self, base_values):
        assert 'affinity' not in pod_spec(base_values)

    def test_topology_spread_enabled_renders_one_constraint(self, base_values):
        values = dict(base_values, topologySpread={'enabled': True})
        constraints = pod_spec(values)['topologySpreadConstraints']
        assert len(constraints) == 1
        assert constraints[0]['topologyKey'] == 'topology.kubernetes.io/zone'
        assert constraints[0]['maxSkew'] == 1

    def test_topology_spread_defaults_to_schedule_anyway(self, base_values):
        """DoNotSchedule leaves pods Pending forever on a single-zone cluster. The
        default has to degrade to an uneven spread instead of not scheduling."""
        values = dict(base_values, topologySpread={'enabled': True})
        assert pod_spec(values)['topologySpreadConstraints'][0]['whenUnsatisfiable'] == 'ScheduleAnyway'

    def test_topology_spread_selects_only_this_release(self, base_values):
        """A selector matching every runner on the cluster would spread tenants
        against each other rather than each tenant across zones."""
        values = dict(base_values, topologySpread={'enabled': True})
        constraint = pod_spec(values)['topologySpreadConstraints'][0]
        assert constraint['labelSelector']['matchLabels']['app'] == 'test-release-matillion-runner-pods'

    def test_affinity_passed_through_verbatim(self, base_values):
        affinity = {
            'nodeAffinity': {
                'requiredDuringSchedulingIgnoredDuringExecution': {
                    'nodeSelectorTerms': [
                        {'matchExpressions': [
                            {'key': 'workload', 'operator': 'In', 'values': ['runner']}
                        ]}
                    ]
                }
            }
        }
        values = dict(base_values, affinity=affinity)
        assert pod_spec(values)['affinity'] == affinity

    def test_pdb_absent_by_default(self, base_values):
        assert find_kind(render(base_values), 'PodDisruptionBudget') is None

    def test_pdb_rendered_when_enabled(self, base_values):
        values = dict(base_values, podDisruptionBudget={'enabled': True})
        pdb = find_kind(render(values), 'PodDisruptionBudget')
        assert pdb is not None
        assert pdb['spec']['selector']['matchLabels']['app'] == 'test-release-matillion-runner-pods'

    def test_pdb_uses_max_unavailable_not_min_available(self, base_values):
        """A fixed minAvailable stops being satisfiable as the HPA scales and then
        blocks every eviction; maxUnavailable cannot reach that state."""
        values = dict(base_values, podDisruptionBudget={'enabled': True})
        spec = find_kind(render(values), 'PodDisruptionBudget')['spec']
        assert spec['maxUnavailable'] == 1
        assert 'minAvailable' not in spec

    def test_pdb_fails_loudly_when_replica_floor_is_one(self, base_values):
        """A budget over a workload that can sit at one replica permits zero
        voluntary evictions, so node drains and cluster upgrades hang forever.
        That has to be an error, not a silent skip that leaves the operator
        believing the workload is protected."""
        values = dict(base_values, podDisruptionBudget={'enabled': True})
        values['hpa'] = dict(base_values['hpa'], enabled=False)
        values['dpcAgent'] = dict(base_values['dpcAgent'], replicas=1)
        stderr = render_failure(values)
        assert 'replica floor is 1' in stderr
        assert 'zero voluntary evictions' in stderr

    def test_pdb_replica_floor_follows_hpa_min_replicas(self, base_values):
        """With the HPA enabled it, not dpcAgent.replicas, owns the replica count,
        so hpa.minReplicas is the floor that matters."""
        values = dict(base_values, podDisruptionBudget={'enabled': True})
        values['dpcAgent'] = dict(base_values['dpcAgent'], replicas=1)
        values['hpa'] = dict(base_values['hpa'], enabled=True, minReplicas=3)
        assert find_kind(render(values), 'PodDisruptionBudget') is not None


class TestProbes:
    """Liveness / readiness probes — item 6."""

    def container(self, values):
        return pod_spec(values)['containers'][0]

    def test_probes_absent_by_default(self, base_values):
        """Off by default: readiness set too tight makes a rolling update look hung,
        and liveness set too tight kills a runner that is legitimately draining."""
        container = self.container(base_values)
        assert 'readinessProbe' not in container
        assert 'livenessProbe' not in container

    def test_readiness_probe_targets_the_actuator_health_endpoint(self, base_values):
        values = dict(base_values, readinessProbe={'enabled': True})
        probe = self.container(values)['readinessProbe']
        assert probe['httpGet']['path'] == '/actuator/health'
        assert probe['httpGet']['port'] == 8080

    def test_liveness_probe_targets_the_actuator_health_endpoint(self, base_values):
        values = dict(base_values, livenessProbe={'enabled': True})
        assert self.container(values)['livenessProbe']['httpGet']['path'] == '/actuator/health'

    def test_liveness_failure_window_outlasts_the_grace_period(self, base_values):
        """The default liveness window must exceed the 43200s termination grace
        period, or a pod draining in-flight tasks is killed before it finishes —
        silently undoing the drain the grace period exists to permit."""
        values = dict(base_values, livenessProbe={'enabled': True})
        probe = self.container(values)['livenessProbe']
        window = probe['periodSeconds'] * probe['failureThreshold']
        assert window > 43200, f'liveness window {window}s must exceed the 43200s grace period'

    def test_liveness_is_more_forgiving_than_readiness(self, base_values):
        """Readiness failing takes a pod out of service and is recoverable; liveness
        failing destroys whatever the runner was executing. Liveness must never be
        the tighter of the two."""
        values = dict(base_values, readinessProbe={'enabled': True}, livenessProbe={'enabled': True})
        container = self.container(values)
        readiness, liveness = container['readinessProbe'], container['livenessProbe']
        assert (liveness['periodSeconds'] * liveness['failureThreshold']
                > readiness['periodSeconds'] * readiness['failureThreshold'])
        assert liveness['initialDelaySeconds'] >= readiness['initialDelaySeconds']

    def test_probe_path_is_overridable(self, base_values):
        """Builds exposing Spring Boot's Kubernetes probe groups can use the more
        precise per-group endpoints."""
        values = dict(base_values,
                      readinessProbe={'enabled': True, 'path': '/actuator/health/readiness'})
        probe = self.container(values)['readinessProbe']
        assert probe['httpGet']['path'] == '/actuator/health/readiness'


class TestMultiTenancy:
    """commonLabels / podAnnotations for shared-platform tenancy — item 4."""

    TENANT_LABELS = {'matillion.com/business-unit': 'grid', 'matillion.com/cost-centre': '4471'}

    def deployment(self, values):
        return find_kind(render(values), 'Deployment')

    def test_no_extra_labels_by_default(self, base_values):
        """Empty commonLabels must add nothing — not a stray key, not a blank line.
        Regression guard for the rendered-output-unchanged rule."""
        assert set(self.deployment(base_values)['metadata']['labels']) == {
            'app', 'helm.sh/chart', 'app.kubernetes.io/name',
            'app.kubernetes.io/instance', 'app.kubernetes.io/version',
            'app.kubernetes.io/managed-by',
        }

    def test_common_labels_applied_to_resource_metadata(self, base_values):
        values = dict(base_values, commonLabels=self.TENANT_LABELS)
        labels = self.deployment(values)['metadata']['labels']
        assert labels['matillion.com/business-unit'] == 'grid'
        assert labels['matillion.com/cost-centre'] == '4471'

    def test_common_labels_applied_to_pods(self, base_values):
        """Pods carry them too, so observability and cost tooling can attribute
        running workload to a tenant rather than only the Kubernetes objects."""
        values = dict(base_values, commonLabels=self.TENANT_LABELS)
        pod_labels = self.deployment(values)['spec']['template']['metadata']['labels']
        assert pod_labels['matillion.com/business-unit'] == 'grid'

    def test_common_labels_never_reach_the_selector(self, base_values):
        """spec.selector is immutable. A commonLabel reaching it turns `helm upgrade`
        of an existing release into an outright failure rather than a rolling
        update, so the selector must stay byte-for-byte as it was."""
        values = dict(base_values, commonLabels=self.TENANT_LABELS)
        assert self.deployment(values)['spec']['selector']['matchLabels'] == {
            'app': 'test-release-matillion-runner-pods',
            'app.kubernetes.io/name': 'matillion-runner',
            'app.kubernetes.io/instance': 'test-release',
        }

    @pytest.mark.parametrize('reserved', [
        'app', 'app.kubernetes.io/name', 'app.kubernetes.io/instance',
    ])
    def test_reserved_selector_labels_rejected(self, base_values, reserved):
        """Caught at template time rather than discovered as a failed upgrade."""
        values = dict(base_values, commonLabels={reserved: 'hijacked'})
        assert f'commonLabels may not set "{reserved}"' in render_failure(values)

    def test_pod_annotations_merge_with_scrape_annotations(self, base_values):
        """Extra annotations must not displace the prometheus.io/* scrape config the
        autoscaling depends on."""
        values = dict(base_values, podAnnotations={'example.com/owner': 'grid-team'})
        annotations = self.deployment(values)['spec']['template']['metadata']['annotations']
        assert annotations['example.com/owner'] == 'grid-team'
        assert annotations['prometheus.io/scrape'] == 'true'
        assert annotations['prometheus.io/port'] == '8080'

    def test_two_releases_get_distinct_pod_labels(self, base_values):
        """Two tenants must not collide on the `app` label that Prometheus scrapes
        and the HPA keys on, or they would scale each other."""
        def app_label(release):
            deployment = find_kind(render(base_values, release=release), 'Deployment')
            return deployment['spec']['template']['metadata']['labels']['app']

        assert app_label('runner-grid') != app_label('runner-retail')

    def test_tenant_example_values_render(self, base_values):
        """The documented onboarding path has to actually work."""
        result = subprocess.run(
            ['helm', 'template', 'runner-grid', RUNNER_CHART,
             '-f', f'{RUNNER_CHART}/values-azure.yaml',
             '-f', f'{RUNNER_CHART}/values-tenant-example.yaml'],
            capture_output=True, text=True,
        )
        assert result.returncode == 0, result.stderr


class TestPrometheusDiscovery:
    """Multi-namespace scrape discovery — item 3."""

    def prometheus_config(self, values):
        """The server's ConfigMap. Matched on the prometheus.yml key rather than the
        name, since the adapter's ConfigMap also ends in `-config`."""
        docs = render(values, chart_path=PROMETHEUS_CHART)
        return next(d for d in docs
                    if d['kind'] == 'ConfigMap' and 'prometheus.yml' in d.get('data', {}))

    def scrape_job(self, values):
        config = self.prometheus_config(values)
        return yaml.safe_load(config['data']['prometheus.yml'])['scrape_configs'][0]

    def egress_rules(self, values):
        docs = render(values, chart_path=PROMETHEUS_CHART, release='test-prom')
        policy = next(d for d in docs
                      if d['kind'] == 'NetworkPolicy'
                      and not d['metadata']['name'].endswith('-adapter'))
        return policy['spec']['egress']

    def test_defaults_unchanged(self):
        """Default discovery still targets the single `matillion` namespace and the
        literal pod label, so existing single-tenant installs are untouched."""
        job = self.scrape_job({})
        assert job['kubernetes_sd_configs'][0]['namespaces']['names'] == ['matillion']
        keep = job['relabel_configs'][0]
        assert keep['action'] == 'keep'
        assert keep['regex'] == 'matillion-runner-pods'

    def test_multiple_namespaces_discovered(self):
        values = {'config': {'scrapeNamespaces': ['bu-grid', 'bu-retail', 'bu-trading']}}
        names = self.scrape_job(values)['kubernetes_sd_configs'][0]['namespaces']['names']
        assert names == ['bu-grid', 'bu-retail', 'bu-trading']

    def test_empty_namespace_list_means_all_namespaces(self):
        """Prometheus treats an omitted `namespaces` block as every namespace. The
        pod-list RBAC is already a ClusterRole, so this needs no extra permissions."""
        values = {'config': {'scrapeNamespaces': []}}
        assert 'namespaces' not in self.scrape_job(values)['kubernetes_sd_configs'][0]

    def test_pod_label_regex_configurable(self):
        """Each release labels its pods `<release>-matillion-runner-pods`, so a
        shared Prometheus needs a pattern rather than one literal name."""
        values = {'config': {'scrapePodLabelRegex': '.*matillion-runner-pods'}}
        assert self.scrape_job(values)['relabel_configs'][0]['regex'] == '.*matillion-runner-pods'

    def test_raw_prometheus_yml_override_wins(self):
        """That key used to hold the whole file. Anyone overriding it must get
        exactly what they asked for, not a recomposed version of it."""
        raw = 'global:\n  scrape_interval: 30s\nscrape_configs: []\n'
        values = {'config': {'prometheusYml': raw, 'scrapeNamespaces': ['ignored']}}
        parsed = yaml.safe_load(self.prometheus_config(values)['data']['prometheus.yml'])
        assert parsed['global']['scrape_interval'] == '30s'
        assert parsed['scrape_configs'] == []

    def test_egress_policy_unchanged_by_default(self):
        """One runner-scrape rule plus the DNS rule, exactly as before."""
        rules = self.egress_rules({})
        scrape_rules = [r for r in rules if any(p.get('port') == 8080 for p in r.get('ports', []))]
        assert len(scrape_rules) == 1
        assert 'namespaceSelector' not in scrape_rules[0]['to'][0]

    def test_additional_namespaces_get_egress_rules(self):
        """The built-in rule uses a bare podSelector, which is namespace-local — so
        discovery alone would find tenants the policy then silently blocks."""
        values = {'networkPolicy': {'additionalScrapeNamespaces': ['bu-retail', 'bu-trading']}}
        rules = self.egress_rules(values)
        namespaces = [
            peer['namespaceSelector']['matchLabels']['kubernetes.io/metadata.name']
            for rule in rules for peer in rule['to'] if 'namespaceSelector' in peer
        ]
        assert namespaces == ['bu-retail', 'bu-trading']

    def test_additional_namespace_rules_target_port_8080(self):
        values = {'networkPolicy': {'additionalScrapeNamespaces': ['bu-retail']}}
        rule = next(r for r in self.egress_rules(values)
                    if any('namespaceSelector' in peer for peer in r['to']))
        assert rule['ports'] == [{'protocol': 'TCP', 'port': 8080}]
        assert rule['to'][0]['podSelector']['matchLabels'] == {'app': 'matillion-runner-pods'}

    def test_null_pod_selector_admits_any_pod_in_namespace(self):
        """NetworkPolicy selectors cannot express the regex service discovery uses,
        so tenants on differing release names need the pod selector dropped.

        `null` rather than `{}`: Helm coalesces maps, so an empty map leaves the
        chart default in place instead of clearing it."""
        values = {'networkPolicy': {
            'additionalScrapeNamespaces': ['bu-retail'],
            'runnerPodSelector': None,
        }}
        rule = next(r for r in self.egress_rules(values)
                    if any('namespaceSelector' in peer for peer in r['to']))
        assert 'podSelector' not in rule['to'][0]


class TestGracePeriodGuardRails:
    """Termination grace period warnings — item 7."""

    def notes(self, values):
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            yaml.dump(values, f)
            values_file = f.name
        try:
            # Server-side dry run, because NOTES is what these tests assert on and
            # helm renders it nowhere else: `helm template` has no --notes, and
            # --show-only cannot select NOTES.txt because it is not a manifest.
            result = subprocess.run(
                ['helm', 'install', '--dry-run', 'test-release', RUNNER_CHART, '-f', values_file],
                capture_output=True, text=True,
            )
            if result.returncode != 0:
                if 'cluster unreachable' in result.stderr.lower():
                    pytest.skip(
                        'NOTES assertions need a reachable cluster, since helm only renders '
                        'NOTES through a server-side dry run. Point kubectl at any cluster to '
                        'run them.'
                    )
                raise AssertionError(f'helm install --dry-run failed: {result.stderr.strip()}')
            return result.stdout.split('NOTES:', 1)[1]
        finally:
            os.unlink(values_file)

    def test_default_grace_period_matches_agent_shutdown_timeout(self, base_values):
        """43200s is matched to the runner's own agent.shutdown.timeout — it is what
        lets a pod refuse to die until its in-flight tasks finish."""
        assert pod_spec(base_values)['terminationGracePeriodSeconds'] == 43200

    def test_no_warnings_at_defaults(self, base_values):
        notes = self.notes(base_values)
        assert 'WARNING' not in notes

    def test_warns_when_grace_period_lowered(self, base_values):
        """Lowering it turns a lossless planned failover into a lossy one, which is
        worth saying out loud at install time."""
        values = dict(base_values)
        values['dpcAgent'] = {
            **base_values['dpcAgent'],
            'dpcAgent': dict(base_values['dpcAgent']['dpcAgent'], gracePeriodSeconds=300),
        }
        notes = self.notes(values)
        assert 'WARNING' in notes
        assert '300s' in notes

    def test_warns_when_liveness_window_undercuts_grace_period(self, base_values):
        values = dict(base_values,
                      livenessProbe={'enabled': True, 'failureThreshold': 3})
        notes = self.notes(values)
        assert 'WARNING' in notes
        assert 'liveness probe' in notes

    def test_notes_when_spread_enabled_without_pdb(self, base_values):
        """Spreading replicas across zones does nothing for maintenance if a drain
        can still take them all at once."""
        values = dict(base_values, topologySpread={'enabled': True})
        assert 'podDisruptionBudget' in self.notes(values)
