#!/usr/bin/env python3
import yaml
import subprocess
import pytest
import os

class TestRunnerChart:
    @pytest.fixture
    def base_values(self):
        return {
            'cloudProvider': 'aws',
            'config': {
                'oauthClientId': 'test-client-id',
                'oauthClientSecret': 'test-client-secret'
            },
            'serviceAccount': {
                'roleArn': 'arn:aws:iam::123456789012:role/test-role'
            },
            'dpcAgent': {
                'dpcAgent': {
                    'env': {
                        'accountId': '12345',
                        'agentId': 'test-agent-id',
                        'matillionRegion': 'us1'
                    },
                    'image': {
                        'repository': 'nginx',
                        'tag': 'latest'
                    }
                }
            },
            'hpa': {
                'maxReplicas': 10,
                'metrics': {
                    'target': {
                        'averageValue': '50'
                    }
                }
            }
        }

    def helm_template(self, values, chart_path='runner/helm/runner'):
        """Helper to render Helm templates with given values"""
        import tempfile

        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            yaml.dump(values, f)
            values_file = f.name

        try:
            result = subprocess.run([
                'helm', 'template', 'test-release', chart_path,
                '-f', values_file
            ], capture_output=True, text=True, check=True)

            # Parse YAML documents
            documents = list(yaml.safe_load_all(result.stdout))
            return [doc for doc in documents if doc is not None]
        finally:
            os.unlink(values_file)

    def find_document_by_kind(self, documents, kind, name=None):
        """Find a specific Kubernetes resource by kind and optionally name"""
        for doc in documents:
            if doc.get('kind') == kind:
                if name is None or doc.get('metadata', {}).get('name', '').endswith(name):
                    return doc
        return None

    def test_deployment_has_main_container(self, base_values):
        """Test that deployment has the main runner container"""
        documents = self.helm_template(base_values)
        deployment = self.find_document_by_kind(documents, 'Deployment')

        assert deployment is not None
        containers = deployment['spec']['template']['spec']['containers']

        # Should have 1 container: main runner (no sidecar)
        assert len(containers) == 1

        main_container = containers[0]
        assert main_container['name'].endswith('-pods')
        assert main_container['image'] == 'nginx:latest'

    def test_runner_exposes_metrics_port(self, base_values):
        """Test that the runner container exposes the metrics port directly"""
        documents = self.helm_template(base_values)
        deployment = self.find_document_by_kind(documents, 'Deployment')

        main_container = deployment['spec']['template']['spec']['containers'][0]
        assert main_container['ports'][0]['containerPort'] == 8080
        assert main_container['ports'][0]['name'] == 'metrics'

    def test_prometheus_annotations(self, base_values):
        """Test Prometheus scraping annotations point to native actuator endpoint"""
        documents = self.helm_template(base_values)
        deployment = self.find_document_by_kind(documents, 'Deployment')

        annotations = deployment['spec']['template']['metadata']['annotations']
        assert annotations['prometheus.io/scrape'] == 'true'
        assert annotations['prometheus.io/port'] == '8080'
        assert annotations['prometheus.io/path'] == '/actuator/prometheus'

    def test_environment_variables(self, base_values):
        """Test that required environment variables are set"""
        documents = self.helm_template(base_values)
        deployment = self.find_document_by_kind(documents, 'Deployment')

        main_container = deployment['spec']['template']['spec']['containers'][0]
        env_vars = {env['name']: env['value'] for env in main_container['env']}

        assert env_vars['ACCOUNT_ID'] == '12345'
        assert env_vars['AGENT_ID'] == 'test-agent-id'
        assert env_vars['MATILLION_REGION'] == 'us1'

    def test_replica_count(self, base_values):
        """Test replica count is configurable"""
        base_values['dpcAgent']['replicas'] = 3

        documents = self.helm_template(base_values)
        deployment = self.find_document_by_kind(documents, 'Deployment')

        assert deployment['spec']['replicas'] == 3

    def test_image_pull_policy(self, base_values):
        """Default is 'Always' (CKV_K8S_15 — kubelet re-validates with the
        registry on every pod start, catches replaced upstream images and
        revoked pull perms). Previously hardcoded, but customers / test
        environments can now legitimately override via the values entry."""
        documents = self.helm_template(base_values)
        deployment = self.find_document_by_kind(documents, 'Deployment')

        main_container = deployment['spec']['template']['spec']['containers'][0]
        assert main_container['imagePullPolicy'] == 'Always'

    def test_image_pull_policy_override(self, base_values):
        """Verify the values override actually reaches the deployment (the
        regression-guard that was missing — previously the template read
        the default but ignored values.yaml entirely)."""
        base_values['dpcAgent']['dpcAgent']['imagePullPolicy'] = 'Never'
        documents = self.helm_template(base_values)
        deployment = self.find_document_by_kind(documents, 'Deployment')

        main_container = deployment['spec']['template']['spec']['containers'][0]
        assert main_container['imagePullPolicy'] == 'Never'

    def test_proxy_and_location_placeholders_dont_leak(self, base_values):
        """The chart's <ProxyHttp> / <ExtensionLibraryLocation> placeholder
        strings used to land in the container verbatim, crashing the agent's
        Spring proxy parser and looping on S3 `Invalid bucket name` errors.
        Defaults are now empty strings; only non-empty overrides are passed."""
        documents = self.helm_template(base_values)
        deployment = self.find_document_by_kind(documents, 'Deployment')
        env = deployment['spec']['template']['spec']['containers'][0].get('env', [])
        env_map = {e['name']: e.get('value', '') for e in env}

        for var in (
            'PROXY_HTTP', 'PROXY_HTTPS', 'PROXY_EXCLUDE',
            'CUSTOM_CERT_LOCATION', 'EXTENSION_LIBRARY_LOCATION',
            'EXTERNAL_DRIVER_LOCATION',
        ):
            # Must not be a literal placeholder; either absent or empty.
            value = env_map.get(var, '')
            assert '<' not in value and '>' not in value, (
                f'{var} still contains a placeholder string: {value!r}. '
                f'values.yaml defaults must be "" (or the env injection must be guarded).'
            )

    def test_service_account(self, base_values):
        """Test service account is properly referenced"""
        documents = self.helm_template(base_values)
        deployment = self.find_document_by_kind(documents, 'Deployment')

        service_account = deployment['spec']['template']['spec']['serviceAccountName']
        assert service_account.endswith('-sa')

    def test_labels_and_selectors(self, base_values):
        """Test that labels and selectors are consistent"""
        documents = self.helm_template(base_values)
        deployment = self.find_document_by_kind(documents, 'Deployment')

        # Check selector matches template labels
        selector_labels = deployment['spec']['selector']['matchLabels']
        template_labels = deployment['spec']['template']['metadata']['labels']

        for key, value in selector_labels.items():
            assert template_labels[key] == value

    def test_missing_required_values(self):
        """Test that missing required values result in placeholder values"""
        minimal_values = {'cloudProvider': 'aws'}

        documents = self.helm_template(minimal_values)
        deployment = self.find_document_by_kind(documents, 'Deployment')

        # Should render but contain placeholder values indicating missing config
        main_container = deployment['spec']['template']['spec']['containers'][0]
        assert '<AgentImageRepository>' in main_container['image']
        assert '<AgentImageTag>' in main_container['image']

        # Environment variables should also contain placeholders
        env_vars = {env['name']: env['value'] for env in main_container['env']}
        assert env_vars['ACCOUNT_ID'] == '<MatillionAccountId>'
        assert env_vars['AGENT_ID'] == '<MatillionAgentId>'

    def test_hpa_configuration(self, base_values):
        """Test HPA is properly configured when enabled"""
        documents = self.helm_template(base_values)

        # Note: HPA might be in a separate template file
        # This test assumes HPA is included in the chart
        hpa = self.find_document_by_kind(documents, 'HorizontalPodAutoscaler')

        if hpa:  # Only test if HPA is present
            assert hpa['spec']['maxReplicas'] == 10
            assert 'scaleTargetRef' in hpa['spec']

    def test_config_secret_reference(self, base_values):
        """Test that config secret is properly referenced"""
        documents = self.helm_template(base_values)
        deployment = self.find_document_by_kind(documents, 'Deployment')

        main_container = deployment['spec']['template']['spec']['containers'][0]
        env_from = main_container.get('envFrom', [])

        secret_refs = [ref for ref in env_from if 'secretRef' in ref]
        assert len(secret_refs) == 1
        assert secret_refs[0]['secretRef']['name'].endswith('-config')

    def test_aws_local_credentials(self, base_values):
        """Test AWS local credentials configuration"""
        # Enable local AWS credentials
        base_values['aws'] = {
            'local': {
                'enabled': True,
                'region': 'us-west-2',
                'accessKeyId': 'AKIAEXAMPLE',
                'secretAccessKey': 'example-secret-key'
            }
        }

        documents = self.helm_template(base_values)

        # Check that AWS local secret is created
        secret = self.find_document_by_kind(documents, 'Secret', '-aws-local')
        assert secret is not None
        assert 'aws-region' in secret['data']
        assert 'aws-access-key-id' in secret['data']
        assert 'aws-secret-access-key' in secret['data']

        # Check that deployment references AWS credentials
        deployment = self.find_document_by_kind(documents, 'Deployment')
        main_container = deployment['spec']['template']['spec']['containers'][0]

        env_vars = {env['name']: env.get('valueFrom', {}).get('secretKeyRef', {}).get('key')
                   for env in main_container['env'] if env.get('valueFrom')}

        assert env_vars.get('AWS_REGION') == 'aws-region'
        assert env_vars.get('AWS_ACCESS_KEY_ID') == 'aws-access-key-id'
        assert env_vars.get('AWS_SECRET_ACCESS_KEY') == 'aws-secret-access-key'

    def test_aws_role_based_auth_without_local(self, base_values):
        """Test that role-based auth still works when local is disabled"""
        documents = self.helm_template(base_values)

        service_account = self.find_document_by_kind(documents, 'ServiceAccount')
        assert service_account is not None

        # Should have role ARN annotation when local is not enabled
        annotations = service_account.get('metadata', {}).get('annotations', {})
        assert 'eks.amazonaws.com/role-arn' in annotations
        assert annotations['eks.amazonaws.com/role-arn'] == 'arn:aws:iam::123456789012:role/test-role'

    def test_termination_grace_period(self, base_values):
        """Test that terminationGracePeriodSeconds is set from values"""
        base_values['dpcAgent']['dpcAgent']['gracePeriodSeconds'] = 43200

        documents = self.helm_template(base_values)
        deployment = self.find_document_by_kind(documents, 'Deployment')

        pod_spec = deployment['spec']['template']['spec']
        assert 'terminationGracePeriodSeconds' in pod_spec, \
            "terminationGracePeriodSeconds must be set in the pod spec"
        assert pod_spec['terminationGracePeriodSeconds'] == 43200

    def test_termination_grace_period_custom_value(self, base_values):
        """Test that terminationGracePeriodSeconds respects custom values"""
        base_values['dpcAgent']['dpcAgent']['gracePeriodSeconds'] = 3600

        documents = self.helm_template(base_values)
        deployment = self.find_document_by_kind(documents, 'Deployment')

        pod_spec = deployment['spec']['template']['spec']
        assert pod_spec['terminationGracePeriodSeconds'] == 3600

    def test_aws_local_credentials_no_role_arn(self, base_values):
        """Test that service account has no role ARN when using local credentials"""
        # Enable local AWS credentials
        base_values['aws'] = {
            'local': {
                'enabled': True,
                'region': 'us-west-2',
                'accessKeyId': 'AKIAEXAMPLE',
                'secretAccessKey': 'example-secret-key'
            }
        }

        documents = self.helm_template(base_values)

        service_account = self.find_document_by_kind(documents, 'ServiceAccount')
        assert service_account is not None

        # Should NOT have role ARN annotation when local is enabled
        annotations = service_account.get('metadata', {}).get('annotations', {})
        assert 'eks.amazonaws.com/role-arn' not in annotations


class TestScriptRunner:
    """Shared Script Runner (scriptRunner.*) — DPC-47328."""

    @pytest.fixture
    def base_values(self):
        return {
            'cloudProvider': 'aws',
            'config': {'oauthClientId': 'id', 'oauthClientSecret': 'secret'},
            'serviceAccount': {'roleArn': 'arn:aws:iam::123456789012:role/agent'},
            'dpcAgent': {
                'dpcAgent': {
                    'env': {
                        'accountId': '12345',
                        'agentId': 'test-agent-id',
                        'matillionRegion': 'us1',
                        'extensionLibraryLocation': 's3://my-libs',
                    },
                    'image': {'repository': 'nginx', 'tag': 'latest'},
                }
            },
            'hpa': {'maxReplicas': 10, 'metrics': {'target': {'averageValue': '50'}}},
        }

    def enabled_values(self, base_values, **overrides):
        v = dict(base_values)
        v['scriptRunner'] = {
            'enabled': True,
            'image': {'repository': 'docker.io/brbajematillion/maia-script-runner', 'tag': 'current'},
            'authorizedKeys': 'ssh-ed25519 AAAATESTKEY agent@matillion',
            'privateKey': 'PRIVATE-KEY-MATERIAL',
            'serviceAccount': {'roleArn': 'arn:aws:iam::123456789012:role/runner'},
        }
        v['scriptRunner'].update(overrides)
        return v

    # reuse TestRunnerChart's render + lookup helpers
    helm_template = TestRunnerChart.helm_template
    find_document_by_kind = TestRunnerChart.find_document_by_kind

    def _runner_docs(self, documents):
        """Resources whose name carries the `script-runner` marker. Distinguishes the
        script-runner Deployment / Service / etc. from the agent's (now also called
        `matillion-runner` post-PR-#80-rename) Deployment / Service / etc."""
        return [d for d in documents
                if 'script-runner' in d.get('metadata', {}).get('name', '')]

    def test_disabled_by_default_renders_no_runner_resources(self, base_values):
        """With scriptRunner absent/disabled, no script-runner resources are rendered."""
        documents = self.helm_template(base_values)
        assert self._runner_docs(documents) == []

    def test_enabled_renders_all_five_resources(self, base_values):
        """enabled: true renders Deployment / Service / Secret / NetworkPolicy / ServiceAccount."""
        documents = self.helm_template(self.enabled_values(base_values))
        kinds = {d['kind'] for d in self._runner_docs(documents)}
        assert kinds == {'Deployment', 'Service', 'Secret', 'NetworkPolicy', 'ServiceAccount'}

    def test_runner_service_publishes_2222(self, base_values):
        """Service publishes 2222 (not the privileged :22) so the agent dials the
        same port everywhere — Service, container, and the deploy NOTES agree."""
        documents = self.helm_template(self.enabled_values(base_values))
        svc = next(d for d in self._runner_docs(documents) if d['kind'] == 'Service')
        port = svc['spec']['ports'][0]
        assert port['port'] == 2222
        assert port['targetPort'] == 'ssh'

    def test_runner_deployment_shape(self, base_values):
        """Runner: 1 replica, RollingUpdate maxUnavailable 0, :22, size-mapped resources, securityContext."""
        documents = self.helm_template(self.enabled_values(base_values))
        dep = next(d for d in self._runner_docs(documents) if d['kind'] == 'Deployment')
        assert dep['spec']['replicas'] == 1
        assert dep['spec']['strategy']['rollingUpdate']['maxUnavailable'] == 0
        # Consistency with the other new resources — namespace metadata present.
        assert dep['metadata']['namespace'] == 'default'
        container = dep['spec']['template']['spec']['containers'][0]
        # Runner listens on the non-privileged port 2222 (the image runs as the
        # mtln user end-to-end). The Service publishes the same 2222 and routes
        # to the named `ssh` port, so the agent dials 2222 everywhere — Service,
        # container, and the deploy NOTES all agree.
        assert container['ports'][0]['containerPort'] == 2222
        # securityContext: defence-in-depth — non-root, no privilege escalation,
        # ALL Linux capabilities dropped so a future image change (e.g. an
        # apt-get install of a setcap'd binary) can't reintroduce one without
        # a chart-level grant.
        sc = container['securityContext']
        assert sc['allowPrivilegeEscalation'] is False
        assert sc['runAsNonRoot'] is True
        assert sc['capabilities']['drop'] == ['ALL']
        # small size from the shared runnerSizes map
        assert container['resources']['requests']['cpu'] == '1'
        assert container['resources']['limits']['memory'] == '4Gi'
        env = {e['name']: e.get('value') for e in container['env']}
        assert env['CLOUD_PROVIDER'] == 'AWS'
        assert env['EXTENSION_LIBRARY_LOCATION'] == 's3://my-libs'

    def test_runner_image_pull_policy_default_and_override(self, base_values):
        """imagePullPolicy defaults to Always (early/interim image) and can be overridden."""
        documents = self.helm_template(self.enabled_values(base_values))
        dep = next(d for d in self._runner_docs(documents) if d['kind'] == 'Deployment')
        assert dep['spec']['template']['spec']['containers'][0]['imagePullPolicy'] == 'Always'

        documents = self.helm_template(
            self.enabled_values(base_values, image={
                'repository': 'docker.io/brbajematillion/maia-script-runner',
                'tag': 'current',
                'pullPolicy': 'IfNotPresent',
            })
        )
        dep = next(d for d in self._runner_docs(documents) if d['kind'] == 'Deployment')
        assert dep['spec']['template']['spec']['containers'][0]['imagePullPolicy'] == 'IfNotPresent'

    def test_runner_size_override(self, base_values):
        """scriptRunner.size selects from the shared t-shirt map independently of the agent."""
        documents = self.helm_template(self.enabled_values(base_values, size='large'))
        dep = next(d for d in self._runner_docs(documents) if d['kind'] == 'Deployment')
        res = dep['spec']['template']['spec']['containers'][0]['resources']
        assert res['requests']['cpu'] == '4'
        assert res['limits']['memory'] == '16Gi'

    def test_runner_secret_projects_only_public_key_to_pod(self, base_values):
        """Secret holds both keys; the pod mounts only the public authorized_keys."""
        documents = self.helm_template(self.enabled_values(base_values))
        secret = next(d for d in self._runner_docs(documents) if d['kind'] == 'Secret')
        assert set(secret['stringData'].keys()) == {'runner_authorized_keys', 'agent_private_key'}
        dep = next(d for d in self._runner_docs(documents) if d['kind'] == 'Deployment')
        vol = next(v for v in dep['spec']['template']['spec']['volumes'] if v['name'] == 'runner-keys')
        projected = [i['key'] for i in vol['secret']['items']]
        assert projected == ['runner_authorized_keys']  # private key never reaches the runner

    def test_agent_gets_runner_host_when_enabled(self, base_values):
        """Agent container gets MTLN_SCRIPT_RUNNER_HOST pointing at the runner service."""
        documents = self.helm_template(self.enabled_values(base_values))
        # Agent Deployment is named `<release>-matillion-runner-app` after the PR #80 rename;
        # the script-runner Deployment ends in `-script-runner`, so `-app` uniquely picks the agent.
        agent = self.find_document_by_kind(documents, 'Deployment', name='-app')
        env = {e['name']: e.get('value') for e in agent['spec']['template']['spec']['containers'][0]['env']}
        assert 'MTLN_SCRIPT_RUNNER_HOST' in env
        assert env['MTLN_SCRIPT_RUNNER_HOST'].endswith('-script-runner')

    def test_agent_has_no_runner_host_when_disabled(self, base_values):
        documents = self.helm_template(base_values)
        agent = self.find_document_by_kind(documents, 'Deployment', name='-app')
        env = {e['name'] for e in agent['spec']['template']['spec']['containers'][0]['env']}
        assert 'MTLN_SCRIPT_RUNNER_HOST' not in env

    def test_agent_netpol_allows_ssh_egress_when_enabled(self, base_values):
        """Agent NetworkPolicy gains a :2222 egress rule to the runner when enabled."""
        documents = self.helm_template(self.enabled_values(base_values))
        # Pick the agent NetworkPolicy (its name doesn't contain `script-runner`).
        agent_np = next(
            d for d in documents
            if d.get('kind') == 'NetworkPolicy'
            and 'script-runner' not in d.get('metadata', {}).get('name', '')
        )
        egress_ports = [p.get('port') for r in agent_np['spec']['egress'] for p in r.get('ports', [])]
        # Pod-level enforcement — match the runner's actual listen port (2222),
        # not the Service mapping.
        assert 2222 in egress_ports

    def test_runner_netpol_ingress_only_from_agent_on_2222(self, base_values):
        documents = self.helm_template(self.enabled_values(base_values))
        runner_np = next(d for d in self._runner_docs(documents) if d['kind'] == 'NetworkPolicy')
        ingress = runner_np['spec']['ingress']
        assert len(ingress) == 1
        # NetworkPolicy enforces at the pod level — uses the runner's actual
        # listen port (2222), not the Service's external :22 mapping.
        assert ingress[0]['ports'][0]['port'] == 2222
        # Ingress selector targets the agent pods specifically.
        selector = ingress[0]['from'][0]['podSelector']['matchLabels']
        assert selector['app'].endswith('-app-pods')

    def test_runner_serviceaccount_aws_role(self, base_values):
        documents = self.helm_template(self.enabled_values(base_values))
        sa = next(d for d in self._runner_docs(documents) if d['kind'] == 'ServiceAccount')
        assert sa['metadata']['annotations']['eks.amazonaws.com/role-arn'] == 'arn:aws:iam::123456789012:role/runner'

    def test_runner_serviceaccount_azure_workload_identity(self, base_values):
        """Runner SA carries the Azure WI client-id annotation on Azure deployments."""
        base_values['cloudProvider'] = 'azure'
        base_values['azure'] = {'workloadIdentity': {'enabled': True, 'clientId': 'agent-wi-client'}}
        values = self.enabled_values(base_values)
        values['scriptRunner']['serviceAccount'] = {'clientId': 'runner-wi-client'}
        documents = self.helm_template(values)
        sa = next(d for d in self._runner_docs(documents) if d['kind'] == 'ServiceAccount')
        annotations = sa['metadata']['annotations']
        # Runner gets its own WI identity, distinct from the agent's.
        assert annotations['azure.workload.identity/client-id'] == 'runner-wi-client'
        # The SA also carries the workload-identity use label.
        assert sa['metadata']['labels']['azure.workload.identity/use'] == 'true'

    def test_runner_serviceaccount_gcp_workload_identity(self, base_values):
        """Runner SA carries the GCP WI gcp-service-account annotation on GCP deployments."""
        base_values['cloudProvider'] = 'gcp'
        base_values['gcp'] = {'workloadIdentity': {'enabled': True,
                                                   'serviceAccountEmail': 'agent-wi@p.iam.gserviceaccount.com'}}
        values = self.enabled_values(base_values)
        values['scriptRunner']['serviceAccount'] = {
            'serviceAccountEmail': 'runner-wi@p.iam.gserviceaccount.com'
        }
        documents = self.helm_template(values)
        sa = next(d for d in self._runner_docs(documents) if d['kind'] == 'ServiceAccount')
        annotations = sa['metadata']['annotations']
        assert annotations['iam.gke.io/gcp-service-account'] == 'runner-wi@p.iam.gserviceaccount.com'
        # GCP WI label distinguishes WI-bound SAs (parallels the agent's pattern).
        assert sa['metadata']['labels']['app.kubernetes.io/gcp-workload-identity'] == 'true'
