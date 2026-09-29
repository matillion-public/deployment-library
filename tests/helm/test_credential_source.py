#!/usr/bin/env python3
"""AWS credential source and caller-supplied library volumes — DPC-54796.

Two extensions, same discipline as DPC-53846: every one is values-gated with a
default that reproduces the previous rendered output, so the tests are paired —
one pinning the default, one exercising the feature.

The default-unchanged half is pinned against golden files generated from
origin/main rather than asserted inline (tests/helm/golden/dpc54796_*.json). That
matters more here than usual: this PR rewrites how the ServiceAccount's identity
annotation is chosen, and the failure mode of getting it wrong is a release that
still renders and still deploys but silently runs with different AWS permissions
than its operator believes. A hand-written expectation would be written from the
same misunderstanding as the bug.

Regenerate deliberately, never to make a red test green:
    git archive origin/main runner/helm/runner | tar -x -C /tmp/base
    # then re-run the generator in the PR description
"""
import json
import os
import shutil
import subprocess
import tempfile

import pytest
import yaml

from test_shared_platform import base_values, find_kind, render, render_failure  # noqa: F401

GOLDEN_DIR = os.path.join(os.path.dirname(__file__), 'golden')
RUNNER_CHART = 'runner/helm/runner'

# Emits the rendered NOTES.txt as a ConfigMap value so `helm template` can reach
# it. `quote` collapses the multi-line text into one escaped YAML scalar, which
# round-trips back through yaml.safe_load unchanged.
NOTES_PROBE = '''apiVersion: v1
kind: ConfigMap
metadata:
  name: notes-probe
data:
  notes: {{ tpl (.Files.Get "notes-source.txt") . | quote }}
'''


def golden(name):
    with open(os.path.join(GOLDEN_DIR, f'dpc54796_{name}.json')) as f:
        return json.load(f)


def render_notes(values):
    """Rendered NOTES.txt for a values set, without needing a cluster.

    NOTES.txt is awkward to get at. `helm template` skips it entirely,
    `--show-only templates/NOTES.txt` errors because it is not a manifest, and
    `helm install --dry-run=client` — the obvious answer — still performs
    Kubernetes version discovery, so it fails with "cluster unreachable"
    wherever there is no kubeconfig. That passes locally and fails in CI, which
    is the worst of the options.

    So: copy the chart to a temp dir, put NOTES.txt somewhere `.Files.Get` can
    read it (it deliberately cannot read templates/), and render it through `tpl`
    in a throwaway probe template. Same template, same context, no cluster. The
    probe lives only in the copy — nothing is added to the shipped chart.
    """
    with tempfile.TemporaryDirectory() as tmp:
        chart = os.path.join(tmp, 'runner')
        shutil.copytree(RUNNER_CHART, chart)
        shutil.copyfile(os.path.join(chart, 'templates', 'NOTES.txt'),
                        os.path.join(chart, 'notes-source.txt'))
        with open(os.path.join(chart, 'templates', 'zz-notes-probe.yaml'), 'w') as f:
            f.write(NOTES_PROBE)

        values_file = os.path.join(tmp, 'values.yaml')
        with open(values_file, 'w') as f:
            yaml.dump(values, f)

        result = subprocess.run(
            ['helm', 'template', 'test-release', chart, '-f', values_file,
             '-s', 'templates/zz-notes-probe.yaml'],
            capture_output=True, text=True, check=True,
        )
        return yaml.safe_load(result.stdout)['data']['notes']


def pod_storage(values, name_suffix=None):
    """The identity + storage surface of a pod spec, shaped to match the goldens."""
    deployment = find_kind(render(values), 'Deployment', name_suffix)
    assert deployment is not None, 'Deployment not rendered'
    spec = deployment['spec']['template']['spec']
    return {
        'serviceAccountName': spec['serviceAccountName'],
        'initContainers': spec.get('initContainers'),
        'volumes': spec['volumes'],
        'volumeMounts': spec['containers'][0]['volumeMounts'],
    }


def script_runner_values(base_values, **overrides):
    script_runner = {
        'enabled': True,
        'image': {'repository': 'nginx', 'tag': 'latest'},
        'serviceAccount': {'roleArn': 'arn:aws:iam::123456789012:role/sr-role'},
        'authorizedKeys': 'ssh-ed25519 AAAA test',
        'privateKey': 'KEY',
    }
    script_runner.update(overrides)
    return {**base_values, 'scriptRunner': script_runner}


def static_values(base_values):
    """The pre-existing way of asking for static keys."""
    return {
        **base_values,
        'serviceAccount': {'roleArn': ''},
        'aws': {'local': {'enabled': True, 'region': 'eu-west-1',
                          'accessKeyId': 'AKIAEXAMPLE', 'secretAccessKey': 'secret'}},
    }


class TestDefaultRenderUnchanged:
    """The upgrade must be a no-op for every release that does not opt in."""

    def test_irsa_service_account_matches_golden(self, base_values):
        assert find_kind(render(base_values), 'ServiceAccount') == golden('sa_irsa')

    def test_legacy_aws_local_service_account_matches_golden(self, base_values):
        """aws.local.enabled predates credentialSource and has to keep working
        untouched — it is the one path a caller could already be on that this
        change could plausibly break."""
        sa = find_kind(render(static_values(base_values)), 'ServiceAccount')
        assert sa == golden('sa_legacy_static')

    def test_legacy_aws_local_still_injects_static_credentials(self, base_values):
        """Not just the SA: the env wiring and the secret must survive too."""
        documents = render(static_values(base_values))
        assert find_kind(documents, 'Secret', '-aws-local') is not None
        container = find_kind(documents, 'Deployment')['spec']['template']['spec']['containers'][0]
        keys = {e['name']: e.get('valueFrom', {}).get('secretKeyRef', {}).get('key')
                for e in container['env'] if e.get('valueFrom')}
        assert keys.get('AWS_REGION') == 'aws-region'
        assert keys.get('AWS_ACCESS_KEY_ID') == 'aws-access-key-id'
        assert keys.get('AWS_SECRET_ACCESS_KEY') == 'aws-secret-access-key'

    def test_agent_pod_storage_matches_golden(self, base_values):
        """No initContainers key, and the three original volumes only."""
        assert pod_storage(base_values) == golden('agent_pod_storage')

    def test_script_runner_pod_storage_matches_golden(self, base_values):
        assert pod_storage(script_runner_values(base_values),
                           '-script-runner') == golden('script_runner_pod_storage')

    def test_service_account_name_helper_agrees_with_previous_inline_spelling(self, base_values):
        """deployment.yaml and serviceaccount.yaml each spelled the fallback name
        inline and now share a helper. A helper that disagreed with the old
        spelling would point the pods at an account the chart never created."""
        base_values['serviceAccount'] = {'roleArn': 'arn:aws:iam::1:role/r', 'name': ''}
        documents = render(base_values)
        sa_name = find_kind(documents, 'ServiceAccount')['metadata']['name']
        bound = find_kind(documents, 'Deployment')['spec']['template']['spec']['serviceAccountName']
        assert sa_name == bound == 'test-release-matillion-runner-sa'


class TestCredentialSourceNode:
    """The DuploCloud case: AWS permissions come from the node instance profile."""

    @pytest.fixture
    def node_values(self, base_values):
        return {**base_values,
                'serviceAccount': {'credentialSource': 'node', 'roleArn': ''}}

    def test_no_role_arn_annotation(self, node_values):
        """The point of the change. While the annotation is present the pod
        identity webhook injects a web-identity token, and that provider sits
        ahead of IMDS — so leaving it on would mask the node profile rather than
        fall back to it."""
        sa = find_kind(render(node_values), 'ServiceAccount')
        assert 'eks.amazonaws.com/role-arn' not in (sa['metadata'].get('annotations') or {})

    def test_service_account_still_created_and_bound(self, node_values):
        documents = render(node_values)
        sa = find_kind(documents, 'ServiceAccount')
        assert sa is not None
        pod = find_kind(documents, 'Deployment')['spec']['template']['spec']
        assert pod['serviceAccountName'] == sa['metadata']['name']

    def test_no_static_credentials_anywhere(self, node_values):
        """`node` must not quietly pull in the static-key path."""
        documents = render(node_values)
        assert find_kind(documents, 'Secret', '-aws-local') is None
        container = find_kind(documents, 'Deployment')['spec']['template']['spec']['containers'][0]
        names = {e['name'] for e in container['env']}
        assert not names & {'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY'}

    def test_script_runner_annotation_also_dropped(self, base_values):
        """Both workloads resolve from the same switch — a script runner left on
        IRSA while the agent moved to the node profile would fail only for Script
        Pushdown, which is a much harder failure to attribute."""
        values = script_runner_values(base_values,
                                      serviceAccount={'roleArn': ''})
        values['serviceAccount'] = {'credentialSource': 'node', 'roleArn': ''}
        sa = find_kind(render(values), 'ServiceAccount', '-script-runner-sa')
        assert sa is not None
        assert 'eks.amazonaws.com/role-arn' not in (sa['metadata'].get('annotations') or {})

    def test_notes_warn_that_permissions_are_node_wide(self, node_values):
        """A node-profile deployment has to announce itself: the runner's
        permissions are now shared with every pod on the node and invisible to
        this chart."""
        notes = render_notes(node_values)
        assert 'EC2 node instance profile' in notes
        assert 's3:ListAllMyBuckets' in notes

    def test_notes_flag_ignored_role_arn(self, base_values):
        """A roleArn left behind after switching to node is inert. Silence there
        would leave an operator believing a role is in play."""
        notes = render_notes({**base_values, 'serviceAccount': {
            'credentialSource': 'node',
            'roleArn': 'arn:aws:iam::123456789012:role/stale'}})
        assert 'roleArn is set but ignored' in notes

    def test_notes_do_not_warn_when_role_arn_is_the_values_placeholder(self, base_values):
        """values.yaml ships roleArn as "<ServiceAccountRoleArn>". Treating that
        as a real setting would fire the warning on every node deployment that
        simply never edited the line."""
        notes = render_notes({**base_values, 'serviceAccount': {
            'credentialSource': 'node', 'roleArn': '<ServiceAccountRoleArn>'}})
        assert 'roleArn is set but ignored' not in notes


class TestCredentialSourceValidation:
    def test_static_is_equivalent_to_the_legacy_flag(self, base_values):
        """credentialSource=static and aws.local.enabled must render the same
        thing, or the new spelling is a trap."""
        legacy = static_values(base_values)
        explicit = {**base_values,
                    'serviceAccount': {'credentialSource': 'static', 'roleArn': ''},
                    'aws': {'local': {'enabled': False, 'region': 'eu-west-1',
                                      'accessKeyId': 'AKIAEXAMPLE',
                                      'secretAccessKey': 'secret'}}}
        assert find_kind(render(explicit), 'ServiceAccount') == \
            find_kind(render(legacy), 'ServiceAccount')
        assert find_kind(render(explicit), 'Secret', '-aws-local') == \
            find_kind(render(legacy), 'Secret', '-aws-local')

    def test_unknown_value_rejected(self, base_values):
        stderr = render_failure({**base_values, 'serviceAccount': {
            'credentialSource': 'nodeprofile', 'roleArn': ''}})
        assert 'must be one of irsa, node, static' in stderr

    def test_explicit_irsa_conflicting_with_aws_local_rejected(self, base_values):
        """Two ways of saying different things at once. Resolving it by
        precedence would silently pick a credential source the operator did not
        choose, so it fails instead."""
        values = static_values(base_values)
        values['serviceAccount'] = {'credentialSource': 'irsa',
                                    'roleArn': 'arn:aws:iam::1:role/r'}
        stderr = render_failure(values)
        assert 'aws.local.enabled=true means static access keys' in stderr

    def test_unset_credential_source_defers_to_aws_local(self, base_values):
        """The compatibility hinge. An empty credentialSource must be
        distinguishable from an explicit "irsa", or every pre-existing
        aws.local.enabled release fails to render on upgrade."""
        values = static_values(base_values)
        values['serviceAccount'] = {'credentialSource': '', 'roleArn': ''}
        assert find_kind(render(values), 'Secret', '-aws-local') is not None

    def test_irsa_without_role_arn_names_the_node_alternative(self, base_values):
        """The error an operator on a non-IRSA cluster hits first. It has to point
        at credentialSource=node, because the intuitive fix — blanking roleArn —
        is exactly what does not work."""
        stderr = render_failure({**base_values, 'serviceAccount': {'roleArn': ''}})
        assert 'serviceAccount.roleArn is required' in stderr
        assert 'credentialSource=node' in stderr


class TestServiceAccountCreate:
    def test_create_false_omits_object_but_still_binds(self, base_values):
        """For a platform-managed account: the chart must not own the object, but
        the pods still have to bind to it by name."""
        values = {**base_values, 'serviceAccount': {
            'create': False, 'name': 'duplo-tenant-sa',
            'credentialSource': 'node', 'roleArn': ''}}
        documents = render(values)
        assert find_kind(documents, 'ServiceAccount') is None
        pod = find_kind(documents, 'Deployment')['spec']['template']['spec']
        assert pod['serviceAccountName'] == 'duplo-tenant-sa'

    def test_create_false_does_not_require_role_arn(self, base_values):
        """The annotation lives on an account the chart does not manage, so
        demanding a roleArn we would never write is pure obstruction."""
        documents = render({**base_values, 'serviceAccount': {
            'create': False, 'name': 'platform-sa', 'roleArn': ''}})
        assert find_kind(documents, 'ServiceAccount') is None

    def test_script_runner_create_false(self, base_values):
        values = script_runner_values(
            base_values, serviceAccount={'create': False, 'name': 'platform-sa', 'roleArn': ''})
        documents = render(values)
        assert find_kind(documents, 'ServiceAccount', '-script-runner-sa') is None
        pod = find_kind(documents, 'Deployment', '-script-runner')['spec']['template']['spec']
        assert pod['serviceAccountName'] == 'platform-sa'

    def test_notes_warn_identity_is_managed_elsewhere(self, base_values):
        notes = render_notes({**base_values, 'serviceAccount': {
            'create': False, 'name': 'platform-sa',
            'credentialSource': 'node', 'roleArn': ''}})
        assert 'serviceAccount.create=false' in notes


class TestCallerSuppliedLibraryVolumes:
    """The alternative to staging Python libraries in object storage: hydrate
    /usr/lib/pythonLibs from an image the customer builds. Both runner images
    already treat that directory as runtime-populated and already have it on the
    interpreter's import path, so this is chart plumbing only."""

    LIBS_IMAGE = 'registry.example.com/our-python-libs:1.4.0'

    def hydration_values(self):
        return {
            'initContainers': [{
                'name': 'python-libs',
                'image': self.LIBS_IMAGE,
                'command': ['sh', '-c', 'cp -a /libs/. /hydrate/'],
                'volumeMounts': [{'name': 'python-libs', 'mountPath': '/hydrate'}],
            }],
            'extraVolumes': [{'name': 'python-libs', 'emptyDir': {}}],
            'extraVolumeMounts': [{'name': 'python-libs',
                                   'mountPath': '/usr/lib/pythonLibs'}],
        }

    def test_agent_hydration_renders_end_to_end(self, base_values):
        values = {**base_values, **self.hydration_values()}
        storage = pod_storage(values)
        assert storage['initContainers'][0]['image'] == self.LIBS_IMAGE
        assert {'name': 'python-libs', 'emptyDir': {}} in storage['volumes']
        assert {'name': 'python-libs', 'mountPath': '/usr/lib/pythonLibs'} \
            in storage['volumeMounts']

    def test_agent_hydration_preserves_chart_volumes(self, base_values):
        """Additive, not replacing. Losing config-volume or tmp-volume here would
        break the runner in a way the new mount would get blamed for."""
        values = {**base_values, **self.hydration_values()}
        names = {v['name'] for v in pod_storage(values)['volumes']}
        assert {'config-volume', 'tmp-volume', 'api-profiles-volume'} <= names

    def test_script_runner_hydration_renders_end_to_end(self, base_values):
        values = script_runner_values(base_values, **self.hydration_values())
        storage = pod_storage(values, '-script-runner')
        assert storage['initContainers'][0]['image'] == self.LIBS_IMAGE
        assert {'name': 'python-libs', 'mountPath': '/usr/lib/pythonLibs'} \
            in storage['volumeMounts']

    def test_script_runner_hydration_preserves_keys_and_tmp(self, base_values):
        """runner-keys and the size-limited /tmp are load-bearing: without the
        first sshd rejects the agent, and without the second a runaway script can
        fill node ephemeral storage."""
        values = script_runner_values(base_values, **self.hydration_values())
        volumes = {v['name']: v for v in pod_storage(values, '-script-runner')['volumes']}
        assert 'runner-keys' in volumes
        assert volumes['tmp-volume']['emptyDir']['sizeLimit'] == '5Gi'

    def test_agent_and_script_runner_hooks_are_independent(self, base_values):
        """Setting the runner's hooks must not silently populate the script
        runner's, and vice versa — they hydrate separately by design."""
        values = script_runner_values(base_values)
        values.update(self.hydration_values())
        assert pod_storage(values)['initContainers'] is not None
        assert pod_storage(values, '-script-runner')['initContainers'] is None


def plain_env(documents, name_suffix=None):
    """Container env as a name -> literal value map, ignoring valueFrom entries."""
    deployment = find_kind(documents, 'Deployment', name_suffix)
    container = deployment['spec']['template']['spec']['containers'][0]
    return {e['name']: e['value'] for e in container['env'] if 'value' in e}


class TestAwsRegion:
    """DPC-55696: region is not a credential, and no source supplied one.

    Only the static path had a region at all, out of the aws-local secret, which
    left every IRSA and node deployment without one — and the script runner
    without one on any path. The failure that produces is worth spelling out
    because it looks nothing like a config error: the pod authenticates fine,
    then dies constructing its first client with NoRegionError. Under Script
    Pushdown it surfaces partway through a customer's script.
    """

    REGION = 'eu-west-2'

    def test_no_region_rendered_by_default(self, base_values):
        """Paired with the tests below: unset must stay a no-op. Making it
        required would break every release already running on IRSA at upgrade
        time, so empty has to remain valid rather than becoming an error."""
        names = set(plain_env(render(base_values)))
        assert not names & {'AWS_REGION', 'AWS_DEFAULT_REGION'}

    def test_script_runner_has_no_region_by_default(self, base_values):
        values = script_runner_values(base_values)
        names = set(plain_env(render(values), '-script-runner'))
        assert not names & {'AWS_REGION', 'AWS_DEFAULT_REGION'}

    def test_irsa_agent_gets_region_from_values(self, base_values):
        """The gap this closes. IRSA hands over credentials but never a region."""
        values = {**base_values, 'aws': {'region': self.REGION}}
        env = plain_env(render(values))
        assert env['AWS_REGION'] == self.REGION
        assert env['AWS_DEFAULT_REGION'] == self.REGION

    def test_node_credential_source_also_gets_region(self, base_values):
        """`node` reaches IMDS for credentials, which likewise carries no region."""
        values = {**base_values,
                  'serviceAccount': {'credentialSource': 'node', 'roleArn': ''},
                  'aws': {'region': self.REGION}}
        env = plain_env(render(values))
        assert env['AWS_REGION'] == self.REGION
        assert env['AWS_DEFAULT_REGION'] == self.REGION

    def test_script_runner_gets_region_on_irsa(self, base_values):
        """The one that matters for Script Pushdown: the runner forwards both
        names into every SSH session, so this is what a pushed-down script ends
        up reading."""
        values = script_runner_values(base_values)
        values['aws'] = {'region': self.REGION}
        env = plain_env(render(values), '-script-runner')
        assert env['AWS_REGION'] == self.REGION
        assert env['AWS_DEFAULT_REGION'] == self.REGION

    def test_static_path_keeps_reading_region_from_the_secret(self, base_values):
        """aws.local.region already worked and must not be downgraded to a
        literal: the secretKeyRef wiring is what existing static releases have,
        and AWS_DEFAULT_REGION joins it from the same key."""
        documents = render(static_values(base_values))
        container = find_kind(documents, 'Deployment')['spec']['template']['spec']['containers'][0]
        keys = {e['name']: e.get('valueFrom', {}).get('secretKeyRef', {}).get('key')
                for e in container['env'] if e.get('valueFrom')}
        assert keys['AWS_REGION'] == 'aws-region'
        assert keys['AWS_DEFAULT_REGION'] == 'aws-region'

    def test_aws_local_region_falls_through_to_the_script_runner(self, base_values):
        """The script runner has no static-credentials path of its own, but a
        static caller has still told the chart a region — reuse it rather than
        making them repeat it under aws.region."""
        values = script_runner_values(static_values(base_values))
        env = plain_env(render(values), '-script-runner')
        assert env['AWS_REGION'] == 'eu-west-1'
        assert env['AWS_DEFAULT_REGION'] == 'eu-west-1'

    def test_aws_region_wins_over_the_legacy_local_region(self, base_values):
        values = script_runner_values(static_values(base_values))
        values['aws'] = {**values['aws'], 'region': self.REGION}
        assert plain_env(render(values), '-script-runner')['AWS_REGION'] == self.REGION

    def test_region_not_rendered_for_non_aws_providers(self, base_values):
        """aws.region is AWS-only — Azure and GCP have their own mechanisms and
        must not pick up AWS_* names from it."""
        values = {**base_values, 'cloudProvider': 'gcp',
                  'aws': {'region': self.REGION},
                  'gcp': {'workloadIdentity': {'enabled': True,
                                               'serviceAccountEmail': 'sa@p.iam.gserviceaccount.com'}}}
        names = set(plain_env(render(values)))
        assert not names & {'AWS_REGION', 'AWS_DEFAULT_REGION'}
