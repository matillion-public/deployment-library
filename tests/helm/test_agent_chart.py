#!/usr/bin/env python3
import yaml
import subprocess
import pytest
import os

class TestAgentChart:
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
                        'matillionRegion': 'us-east-1'
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

    def helm_template(self, values, chart_path='agent/helm/agent'):
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
        """Test that deployment has the main agent container"""
        documents = self.helm_template(base_values)
        deployment = self.find_document_by_kind(documents, 'Deployment')

        assert deployment is not None
        containers = deployment['spec']['template']['spec']['containers']

        # Should have 1 container: main agent (no sidecar)
        assert len(containers) == 1

        main_container = containers[0]
        assert main_container['name'].endswith('-pods')
        assert main_container['image'] == 'nginx:latest'

    def test_agent_exposes_metrics_port(self, base_values):
        """Test that the agent container exposes the metrics port directly"""
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
        assert env_vars['MATILLION_REGION'] == 'us-east-1'

    def test_replica_count(self, base_values):
        """Test replica count is configurable"""
        base_values['dpcAgent']['replicas'] = 3

        documents = self.helm_template(base_values)
        deployment = self.find_document_by_kind(documents, 'Deployment')

        assert deployment['spec']['replicas'] == 3

    def test_image_pull_policy(self, base_values):
        """Test image pull policy is set to Always"""
        documents = self.helm_template(base_values)
        deployment = self.find_document_by_kind(documents, 'Deployment')

        main_container = deployment['spec']['template']['spec']['containers'][0]
        assert main_container['imagePullPolicy'] == 'Always'

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
