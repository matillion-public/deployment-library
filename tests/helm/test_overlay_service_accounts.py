"""Service account names rendered by the per-cloud overlays (DPC-58375).

The Azure and GCP Terraform creates its workload-identity trust for fixed
service account names. If the chart renders anything else, the token exchange
fails and the runner never becomes ready, with nothing in the runner's own logs
pointing at the name. These tests pin the names for every release name, since
the bug was a fallback that only matched one particular release name.
"""
import subprocess

import pytest
import yaml

RUNNER_CHART = 'runner/helm/runner'

# The names modules/azure/aks/variables.tf and modules/gcp/gke/main.tf default to.
RUNNER_SA = 'matillion-runner-sa'
SCRIPT_RUNNER_SA = 'matillion-runner-script-runner-sa'

RELEASES = ['matillion-runner', 'matillion', 'e2e', 'bu-grid']

# Just enough on top of each overlay to satisfy the chart's `required` checks.
REQUIRED = {
    'azure': [
        '--set', 'azure.workloadIdentity.clientId=00000000-0000-0000-0000-000000000000',
        '--set', 'scriptRunner.serviceAccount.clientId=00000000-0000-0000-0000-000000000001',
    ],
    'gcp': [
        '--set', 'gcp.workloadIdentity.serviceAccountEmail=runner@p.iam.gserviceaccount.com',
        '--set', 'scriptRunner.serviceAccount.serviceAccountEmail=sr@p.iam.gserviceaccount.com',
    ],
}


def service_accounts(cloud, release):
    """Render the overlay with the script runner enabled and map each pod's
    Deployment name to the service account it runs as."""
    result = subprocess.run(
        ['helm', 'template', release, RUNNER_CHART, '-n', 'matillion',
         '-f', f'{RUNNER_CHART}/values-{cloud}.yaml',
         '--set', 'scriptRunner.enabled=true',
         '--set', 'scriptRunner.authorizedKeys=ssh-ed25519 AAAA test',
         *REQUIRED[cloud]],
        capture_output=True, text=True, check=True,
    )
    docs = [d for d in yaml.safe_load_all(result.stdout) if d]
    created = {d['metadata']['name'] for d in docs if d['kind'] == 'ServiceAccount'}
    used = {d['metadata']['name']: d['spec']['template']['spec']['serviceAccountName']
            for d in docs if d['kind'] == 'Deployment'}
    return created, used


@pytest.mark.parametrize('cloud', ['azure', 'gcp'])
@pytest.mark.parametrize('release', RELEASES)
def test_overlay_renders_the_names_terraform_trusts(cloud, release):
    created, used = service_accounts(cloud, release)
    assert created == {RUNNER_SA, SCRIPT_RUNNER_SA}
    runner = next(sa for name, sa in used.items() if 'script-runner' not in name)
    script_runner = next(sa for name, sa in used.items() if 'script-runner' in name)
    assert runner == RUNNER_SA
    assert script_runner == SCRIPT_RUNNER_SA


@pytest.mark.parametrize('cloud', ['azure', 'gcp'])
def test_explicit_override_still_wins(cloud):
    """Customers who also change the Terraform variable can still rename them."""
    result = subprocess.run(
        ['helm', 'template', 'e2e', RUNNER_CHART, '-n', 'matillion',
         '-f', f'{RUNNER_CHART}/values-{cloud}.yaml',
         '--set', 'serviceAccount.name=custom-runner-sa',
         *REQUIRED[cloud]],
        capture_output=True, text=True, check=True,
    )
    docs = [d for d in yaml.safe_load_all(result.stdout) if d]
    assert {d['metadata']['name'] for d in docs if d['kind'] == 'ServiceAccount'} \
        == {'custom-runner-sa'}
