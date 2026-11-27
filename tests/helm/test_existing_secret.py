#!/usr/bin/env python3
"""config.existingSecret — the runner's OAuth credentials from a Secret the
customer manages (DPC-64049).

By default the chart builds <fullname>-config from config.oauthClientId and
config.oauthClientSecret, so the credentials pass through Helm values and sit
in the release record. With existingSecret set the chart creates no Secret and
both places that read it (envFrom and the config volume) point at the named
one instead, so a Secret synced from Azure Key Vault, Secrets Manager or Secret
Manager is what the runner uses. Unset, the output must not change.
"""
import copy

import pytest

from test_script_execution import azure, gcp
from test_shared_platform import base_values, find_kind, render, render_failure  # noqa: F401

EXISTING = 'runner-oauth'


def with_existing_secret(values, oauth=None):
    """existingSecret set; `oauth` replaces config.oauthClient* (None drops
    them, so the chart's placeholder defaults apply)."""
    values = copy.deepcopy(values)
    values['config'] = {'existingSecret': EXISTING, **(oauth or {})}
    return values


def runner_pod_spec(documents):
    deployment = find_kind(documents, 'Deployment', '-app')
    assert deployment is not None, 'runner Deployment not rendered'
    return deployment['spec']['template']['spec']


def secret_refs(documents):
    """(envFrom secretRef names, config-volume secretName) on the runner pod."""
    spec = runner_pod_spec(documents)
    env_from = [e['secretRef']['name'] for e in spec['containers'][0].get('envFrom', [])
                if 'secretRef' in e]
    volume = next(v for v in spec['volumes'] if v['name'] == 'config-volume')
    return env_from, volume['secret']['secretName']


def oauth_key_refs(documents):
    """{env name: (secret name, key)} for the OAuth variables read by secretKeyRef."""
    container = runner_pod_spec(documents)['containers'][0]
    return {
        e['name']: (e['valueFrom']['secretKeyRef']['name'], e['valueFrom']['secretKeyRef']['key'])
        for e in container.get('env', [])
        if e['name'].startswith('OAUTH_') and 'secretKeyRef' in e.get('valueFrom', {})
    }


def oauth_secrets(documents):
    return [d for d in documents if d.get('kind') == 'Secret'
            and 'OAUTH_CLIENT_ID' in (d.get('stringData') or {})]


class TestDefault:
    def test_chart_creates_the_config_secret_from_values(self, base_values):
        documents = render(base_values)
        secrets = oauth_secrets(documents)
        assert [s['metadata']['name'] for s in secrets] == ['test-release-matillion-runner-config']
        assert secrets[0]['stringData'] == {
            'OAUTH_CLIENT_ID': 'test-client-id',
            'OAUTH_CLIENT_SECRET': 'test-client-secret',
        }

    def test_runner_reads_the_chart_secret(self, base_values):
        documents = render(base_values)
        env_from, volume = secret_refs(documents)
        assert env_from == ['test-release-matillion-runner-config']
        assert volume == 'test-release-matillion-runner-config'
        assert oauth_key_refs(documents) == {}

    def test_oauth_values_still_required(self, base_values):
        values = copy.deepcopy(base_values)
        values['config'] = {'oauthClientId': '', 'oauthClientSecret': 'x'}
        assert 'config.oauthClientId is required' in render_failure(values)


class TestExistingSecret:
    @pytest.mark.parametrize('provider', [lambda v: v, azure, gcp], ids=['aws', 'azure', 'gcp'])
    def test_runner_reads_the_named_secret_on_every_cloud(self, base_values, provider):
        """Each key by name, so kubelet refuses to start the container, naming
        the key, when the customer's Secret lacks one; envFrom would start it
        without credentials."""
        documents = render(with_existing_secret(provider(base_values)))
        env_from, volume = secret_refs(documents)
        assert env_from == []
        assert volume == EXISTING
        assert oauth_key_refs(documents) == {
            'OAUTH_CLIENT_ID': (EXISTING, 'OAUTH_CLIENT_ID'),
            'OAUTH_CLIENT_SECRET': (EXISTING, 'OAUTH_CLIENT_SECRET'),
        }

    def test_keys_are_read_in_env_direct_mode(self, base_values):
        values = with_existing_secret(base_values)
        values['dpcAgent']['dpcAgent']['env'] = {
            'direct': [{'name': 'ACCOUNT_ID', 'value': '12345'}],
        }
        assert set(oauth_key_refs(render(values))) == {'OAUTH_CLIENT_ID', 'OAUTH_CLIENT_SECRET'}

    def test_rejects_the_chart_secret_name(self, base_values):
        """Helm would delete it on upgrade, since the release still owns it."""
        values = copy.deepcopy(base_values)
        values['config']['existingSecret'] = 'test-release-matillion-runner-config'
        assert 'helm upgrade would delete it' in render_failure(values)

    @pytest.mark.parametrize('name', [' ', 'Runner-OAuth', 'runner_oauth', '-runner'])
    def test_rejects_an_invalid_secret_name(self, base_values, name):
        values = with_existing_secret(base_values)
        values['config']['existingSecret'] = name
        assert 'is not a valid Secret name' in render_failure(values)

    def test_chart_creates_no_secret_for_the_credentials(self, base_values):
        documents = render(with_existing_secret(base_values))
        assert oauth_secrets(documents) == []
        assert find_kind(documents, 'Secret', '-config') is None

    def test_oauth_values_not_required(self, base_values):
        """The customer has nothing to put in them, and `required` must not
        force a dummy value into the release record."""
        values = with_existing_secret(base_values, {'oauthClientId': '', 'oauthClientSecret': ''})
        _, volume = secret_refs(render(values))
        assert volume == EXISTING

    def test_csi_volume_from_the_readme_reaches_the_runner(self, base_values):
        """The Secrets Store CSI driver only syncs the Secret while a pod mounts
        its volume, so the README example mounts it on the runner itself."""
        values = with_existing_secret(azure(base_values))
        values['extraVolumes'] = [{
            'name': 'runner-oauth',
            'csi': {'driver': 'secrets-store.csi.k8s.io', 'readOnly': True,
                    'volumeAttributes': {'secretProviderClass': 'runner-oauth'}},
        }]
        values['extraVolumeMounts'] = [
            {'name': 'runner-oauth', 'mountPath': '/mnt/runner-oauth', 'readOnly': True},
        ]
        spec = runner_pod_spec(render(values))
        volume = next(v for v in spec['volumes'] if v['name'] == 'runner-oauth')
        assert volume['csi']['volumeAttributes'] == {'secretProviderClass': 'runner-oauth'}
        mounts = {m['name']: m['mountPath'] for m in spec['containers'][0]['volumeMounts']}
        assert mounts['runner-oauth'] == '/mnt/runner-oauth'

    def test_oauth_values_ignored_when_also_set(self, base_values):
        """A values file copied from an example still carries both; they must
        not reach any rendered object."""
        values = with_existing_secret(
            base_values, {'oauthClientId': 'stale-id', 'oauthClientSecret': 'stale-secret'})
        documents = render(values)
        assert 'stale-secret' not in repr(documents)
        assert 'stale-id' not in repr(documents)
