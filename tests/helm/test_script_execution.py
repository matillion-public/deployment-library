#!/usr/bin/env python3
"""disableScriptExecution — stop Python Script and Bash Script on the runner.

The runner starts both components through MTLN_PYTHON_3_COMMAND and
MTLN_BASH_COMMAND, so pointing those at paths that do not exist (with
SCRIPT_OOM_PROTECTION_ENABLED=false alongside) makes them fail at Run. These are
internal runner settings rather than a product toggle, so the chart owns the
exact values and these tests pin them: off by default, all three together when
on, on every cloud, in env.direct mode too, and never on the script runner pod,
which must keep running Script Pushdown.
"""
import copy

import pytest

from test_credential_source import render_notes, script_runner_values
from test_shared_platform import base_values, find_kind, render  # noqa: F401

DISABLED_ENV = {
    'SCRIPT_OOM_PROTECTION_ENABLED': 'false',
    'MTLN_PYTHON_3_COMMAND': '/python-script-disabled-on-this-runner',
    'MTLN_BASH_COMMAND': '/bash-script-disabled-on-this-runner',
}

NOTES_MARKER = 'Python Script and Bash Script are DISABLED on this runner'


def disabled(values):
    return {**copy.deepcopy(values), 'disableScriptExecution': True}


def runner_env(values):
    """The runner container's env as {name: value}."""
    deployment = find_kind(render(values), 'Deployment', '-app')
    assert deployment is not None, 'runner Deployment not rendered'
    container = deployment['spec']['template']['spec']['containers'][0]
    return {e['name']: e.get('value') for e in container.get('env', [])}


def runner_env_entries(values):
    """The runner container's env as an ordered list of entries."""
    deployment = find_kind(render(values), 'Deployment', '-app')
    container = deployment['spec']['template']['spec']['containers'][0]
    return container.get('env', [])


def script_runner_env(values):
    deployment = find_kind(render(values), 'Deployment', '-script-runner')
    assert deployment is not None, 'script runner Deployment not rendered'
    container = deployment['spec']['template']['spec']['containers'][0]
    return {e['name']: e.get('value') for e in container.get('env', [])}


def azure(values):
    values = copy.deepcopy(values)
    values['cloudProvider'] = 'azure'
    values.pop('serviceAccount', None)
    values['azure'] = {'workloadIdentity': {'enabled': True, 'clientId': 'wi-client'}}
    return values


def gcp(values):
    values = copy.deepcopy(values)
    values['cloudProvider'] = 'gcp'
    values.pop('serviceAccount', None)
    values['gcp'] = {'workloadIdentity': {'enabled': True,
                                          'serviceAccountEmail': 'r@p.iam.gserviceaccount.com'}}
    return values


class TestDefault:
    def test_off_by_default(self, base_values):
        env = runner_env(base_values)
        assert not set(DISABLED_ENV) & set(env)

    def test_notes_silent_by_default(self, base_values):
        assert NOTES_MARKER not in render_notes(base_values)


class TestEnabled:
    @pytest.mark.parametrize('provider', [lambda v: v, azure, gcp], ids=['aws', 'azure', 'gcp'])
    def test_sets_all_three_on_every_cloud(self, base_values, provider):
        env = runner_env(disabled(provider(base_values)))
        assert {k: env.get(k) for k in DISABLED_ENV} == DISABLED_ENV

    def test_leaves_the_runners_own_variables_alone(self, base_values):
        before = runner_env(base_values)
        after = runner_env(disabled(base_values))
        assert {k: after[k] for k in before} == before

    def test_applies_in_env_direct_mode(self, base_values):
        """env.direct replaces the chart's default variables wholesale. The
        switch must not depend on that branch, or a direct-mode release that
        turns it on would silently keep running scripts."""
        values = copy.deepcopy(base_values)
        values['dpcAgent']['dpcAgent']['env'] = {
            'direct': [{'name': 'ACCOUNT_ID', 'value': '12345'}],
        }
        env = runner_env(disabled(values))
        assert {k: env.get(k) for k in DISABLED_ENV} == DISABLED_ENV

    def test_overrides_colliding_env_direct_entries(self, base_values):
        """Kubernetes keeps the last of two entries with the same name."""
        values = copy.deepcopy(base_values)
        values['dpcAgent']['dpcAgent']['env'] = {
            'direct': [
                {'name': 'MTLN_PYTHON_3_COMMAND', 'value': '/usr/bin/python3'},
                {'name': 'MTLN_BASH_COMMAND', 'value': '/bin/bash'},
            ],
        }
        env = runner_env(disabled(values))
        assert {k: env.get(k) for k in DISABLED_ENV} == DISABLED_ENV

    def test_overrides_colliding_env_from_secret_entries(self, base_values):
        values = copy.deepcopy(base_values)
        values['dpcAgent']['dpcAgent']['env'] = {
            'fromSecret': [
                {'name': 'MTLN_PYTHON_3_COMMAND', 'secretName': 's', 'secretKey': 'python'},
                {'name': 'SCRIPT_OOM_PROTECTION_ENABLED', 'secretName': 's', 'secretKey': 'oom'},
            ],
        }
        env = runner_env(disabled(values))
        assert {k: env.get(k) for k in DISABLED_ENV} == DISABLED_ENV

    def test_entries_are_last_in_the_env_list(self, base_values):
        values = copy.deepcopy(base_values)
        values['dpcAgent']['dpcAgent']['env'] = {
            'fromSecret': [{'name': 'EXTRA', 'secretName': 's', 'secretKey': 'k'}],
        }
        names = [e['name'] for e in runner_env_entries(disabled(values))]
        assert names[-len(DISABLED_ENV):] == list(DISABLED_ENV)

    def test_script_runner_pod_is_untouched(self, base_values):
        """Script Pushdown runs on the script runner pod and must keep working."""
        values = disabled(script_runner_values(base_values))
        assert not set(DISABLED_ENV) & set(script_runner_env(values))
        assert 'MTLN_SCRIPT_RUNNER_HOST' in runner_env(values)

    def test_notes_explain_the_run_time_error(self, base_values):
        notes = render_notes(disabled(base_values))
        assert NOTES_MARKER in notes
        assert 'Cannot run program "/python-script-disabled-on-this-runner"' in notes
