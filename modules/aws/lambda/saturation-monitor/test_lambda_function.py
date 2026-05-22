#!/usr/bin/env python3
"""
Unit tests for ECS Runner Saturation Monitor Lambda function
"""

import unittest
import json
import os
from unittest.mock import Mock, patch, MagicMock
from datetime import datetime

# Import the Lambda function
import lambda_function


class TestECSRunnerSaturationMonitor(unittest.TestCase):
    """Test cases for ECS Runner Saturation Monitor"""

    def setUp(self):
        """Set up test fixtures"""
        self.monitor = lambda_function.ECSRunnerSaturationMonitor()
        
        # Mock environment variables
        self.env_patcher = patch.dict(os.environ, {
            'RUNNER_SERVICE_INDICATORS': 'test-agent,matillion',
            'CLOUDWATCH_NAMESPACE': 'Test/RunnerSaturation',
            'LOG_LEVEL': 'DEBUG'
        })
        self.env_patcher.start()

    def tearDown(self):
        """Clean up after tests"""
        self.env_patcher.stop()

    def test_is_runner_service_default_indicators(self):
        """Test runner service detection with default indicators"""
        # Test with default environment
        with patch.dict(os.environ, {'RUNNER_SERVICE_INDICATORS': 'matillion,agent,dpc'}, clear=False):
            monitor = lambda_function.ECSRunnerSaturationMonitor()
            
            # Should match
            self.assertTrue(monitor._is_runner_service("matillion-prod-service", {}))
            self.assertTrue(monitor._is_runner_service("my-agent-worker", {}))
            self.assertTrue(monitor._is_runner_service("dpc-processor", {}))
            self.assertTrue(monitor._is_runner_service("MATILLION-SERVICE", {}))  # Case insensitive
            
            # Should not match
            self.assertFalse(monitor._is_runner_service("web-server", {}))
            self.assertFalse(monitor._is_runner_service("database", {}))

    def test_is_runner_service_custom_indicators(self):
        """Test runner service detection with custom indicators"""
        with patch.dict(os.environ, {'RUNNER_SERVICE_INDICATORS': 'worker,processor'}, clear=False):
            monitor = lambda_function.ECSRunnerSaturationMonitor()
            
            # Should match custom indicators
            self.assertTrue(monitor._is_runner_service("data-worker", {}))
            self.assertTrue(monitor._is_runner_service("task-processor", {}))
            
            # Should not match default indicators
            self.assertFalse(monitor._is_runner_service("matillion-service", {}))

    def test_extract_agent_id_from_environment(self):
        """Test agent ID extraction from task definition environment"""
        mock_task = {
            'taskDefinitionArn': 'arn:aws:ecs:region:account:task-definition/test:1',
            'taskArn': 'arn:aws:ecs:region:account:task/cluster/abc123'
        }
        
        mock_task_def = {
            'taskDefinition': {
                'containerDefinitions': [{
                    'environment': [
                        {'name': 'OTHER_VAR', 'value': 'other'},
                        {'name': 'AGENT_ID', 'value': 'test-agent-001'}
                    ]
                }]
            }
        }
        
        with patch.object(self.monitor.ecs, 'describe_task_definition', return_value=mock_task_def):
            agent_id = self.monitor._extract_agent_id(mock_task)
            self.assertEqual(agent_id, 'test-agent-001')

    def test_extract_agent_id_fallback_to_task_id(self):
        """Test agent ID fallback to task ID when environment variable not found"""
        mock_task = {
            'taskDefinitionArn': 'arn:aws:ecs:region:account:task-definition/test:1',
            'taskArn': 'arn:aws:ecs:region:account:task/cluster/abc123def456'
        }
        
        mock_task_def = {
            'taskDefinition': {
                'containerDefinitions': [{
                    'environment': []
                }]
            }
        }
        
        with patch.object(self.monitor.ecs, 'describe_task_definition', return_value=mock_task_def):
            agent_id = self.monitor._extract_agent_id(mock_task)
            self.assertEqual(agent_id, 'abc123def456')

    def test_get_task_private_ip(self):
        """Test private IP extraction from ECS task"""
        mock_task = {
            'attachments': [{
                'type': 'ElasticNetworkInterface',
                'details': [
                    {'name': 'networkInterfaceId', 'value': 'eni-123'},
                    {'name': 'privateIPv4Address', 'value': '10.0.1.100'},
                    {'name': 'subnetId', 'value': 'subnet-123'}
                ]
            }]
        }
        
        private_ip = self.monitor._get_task_private_ip(mock_task)
        self.assertEqual(private_ip, '10.0.1.100')

    def test_get_task_private_ip_not_found(self):
        """Test private IP extraction when not available"""
        mock_task = {
            'attachments': [{
                'type': 'SomeOtherType',
                'details': []
            }]
        }
        
        private_ip = self.monitor._get_task_private_ip(mock_task)
        self.assertIsNone(private_ip)

    @patch('urllib.request.urlopen')
    def test_fetch_runner_metrics_success(self, mock_urlopen):
        """Test successful metrics fetching"""
        # Mock HTTP response
        mock_response = MagicMock()
        mock_response.getcode.return_value = 200
        mock_response.read.return_value = json.dumps({
            'activeTaskCount': 5,
            'activeRequestCount': 3,
            'openSessionsCount': 10,
            'agentStatus': 'RUNNING'
        }).encode('utf-8')
        
        mock_urlopen.return_value.__enter__.return_value = mock_response
        
        runner_info = {
            'private_ip': '10.0.1.100',
            'task_arn': 'arn:aws:ecs:region:account:task/cluster/abc123'
        }
        
        metrics = self.monitor.fetch_runner_metrics(runner_info)
        
        self.assertIsNotNone(metrics)
        self.assertEqual(metrics['activeTaskCount'], 5)
        self.assertEqual(metrics['activeRequestCount'], 3)
        self.assertEqual(metrics['openSessionsCount'], 10)
        self.assertEqual(metrics['agentStatus'], 'RUNNING')

    @patch('urllib.request.urlopen')
    def test_fetch_runner_metrics_failure(self, mock_urlopen):
        """Test metrics fetching failure"""
        # Mock HTTP error
        mock_urlopen.side_effect = Exception("Connection refused")
        
        runner_info = {
            'private_ip': '10.0.1.100',
            'task_arn': 'arn:aws:ecs:region:account:task/cluster/abc123'
        }
        
        metrics = self.monitor.fetch_runner_metrics(runner_info)
        self.assertIsNone(metrics)

    def test_fetch_runner_metrics_no_private_ip(self):
        """Test metrics fetching with no private IP"""
        runner_info = {
            'private_ip': None,
            'task_arn': 'arn:aws:ecs:region:account:task/cluster/abc123'
        }
        
        metrics = self.monitor.fetch_runner_metrics(runner_info)
        self.assertIsNone(metrics)

    @patch.object(lambda_function.ECSRunnerSaturationMonitor, 'cloudwatch')
    def test_publish_metrics_to_cloudwatch(self, mock_cloudwatch):
        """Test CloudWatch metrics publishing"""
        runner_info = {
            'cluster_name': 'test-cluster',
            'service_name': 'test-service',
            'agent_id': 'agent-001'
        }
        
        metrics_data = {
            'activeTaskCount': 15,
            'activeRequestCount': 8,
            'openSessionsCount': 25,
            'agentStatus': 'RUNNING'
        }
        
        self.monitor.publish_metrics_to_cloudwatch(runner_info, metrics_data)
        
        # Verify CloudWatch put_metric_data was called
        mock_cloudwatch.put_metric_data.assert_called_once()
        
        # Check the call arguments
        call_args = mock_cloudwatch.put_metric_data.call_args
        self.assertEqual(call_args[1]['Namespace'], 'ECS/RunnerSaturation')
        
        metric_data = call_args[1]['MetricData']
        self.assertEqual(len(metric_data), 4)  # 4 metrics
        
        # Check specific metrics
        metric_names = [m['MetricName'] for m in metric_data]
        self.assertIn('ActiveTaskCount', metric_names)
        self.assertIn('ActiveRequestCount', metric_names)
        self.assertIn('OpenSessionsCount', metric_names)
        self.assertIn('RunnerStatus', metric_names)
        
        # Check dimensions
        for metric in metric_data:
            dimensions = {d['Name']: d['Value'] for d in metric['Dimensions']}
            self.assertEqual(dimensions['ClusterName'], 'test-cluster')
            self.assertEqual(dimensions['ServiceName'], 'test-service')
            self.assertEqual(dimensions['RunnerId'], 'agent-001')

    def test_publish_metrics_agent_status_values(self):
        """Test agent status metric value conversion"""
        with patch.object(self.monitor, 'cloudwatch') as mock_cloudwatch:
            runner_info = {
                'cluster_name': 'test-cluster',
                'service_name': 'test-service',
                'agent_id': 'agent-001'
            }
            
            # Test RUNNING status
            metrics_data = {'agentStatus': 'RUNNING'}
            self.monitor.publish_metrics_to_cloudwatch(runner_info, metrics_data)
            
            call_args = mock_cloudwatch.put_metric_data.call_args
            runner_status_metric = next(m for m in call_args[1]['MetricData'] if m['MetricName'] == 'RunnerStatus')
            self.assertEqual(runner_status_metric['Value'], 1.0)
            
            # Test non-RUNNING status
            metrics_data = {'agentStatus': 'STOPPED'}
            self.monitor.publish_metrics_to_cloudwatch(runner_info, metrics_data)
            
            call_args = mock_cloudwatch.put_metric_data.call_args
            runner_status_metric = next(m for m in call_args[1]['MetricData'] if m['MetricName'] == 'RunnerStatus')
            self.assertEqual(runner_status_metric['Value'], 0.0)

    @patch.object(lambda_function.ECSRunnerSaturationMonitor, 'discover_runner_services')
    @patch.object(lambda_function.ECSRunnerSaturationMonitor, 'fetch_runner_metrics')
    @patch.object(lambda_function.ECSRunnerSaturationMonitor, 'publish_metrics_to_cloudwatch')
    def test_monitor_all_runners_success(self, mock_publish, mock_fetch, mock_discover):
        """Test complete monitoring workflow"""
        # Mock discovered runners
        mock_discover.return_value = [
            {
                'cluster_name': 'cluster1',
                'service_name': 'service1',
                'agent_id': 'agent1',
                'private_ip': '10.0.1.100'
            },
            {
                'cluster_name': 'cluster2',
                'service_name': 'service2',
                'agent_id': 'agent2',
                'private_ip': '10.0.1.101'
            }
        ]
        
        # Mock fetched metrics
        mock_fetch.return_value = {
            'activeTaskCount': 5,
            'activeRequestCount': 2,
            'openSessionsCount': 8,
            'agentStatus': 'RUNNING'
        }
        
        # Run monitoring
        results = self.monitor.monitor_all_runners()
        
        # Verify results
        self.assertEqual(results['runners_discovered'], 2)
        self.assertEqual(results['runners_monitored'], 2)
        self.assertEqual(results['metrics_published'], 8)  # 4 metrics × 2 runners
        self.assertEqual(len(results['errors']), 0)
        
        # Verify methods were called correctly
        mock_discover.assert_called_once()
        self.assertEqual(mock_fetch.call_count, 2)
        self.assertEqual(mock_publish.call_count, 2)

    @patch.object(lambda_function.ECSRunnerSaturationMonitor, 'discover_runner_services')
    def test_monitor_all_runners_no_services(self, mock_discover):
        """Test monitoring when no runner services are discovered"""
        mock_discover.return_value = []
        
        results = self.monitor.monitor_all_runners()
        
        self.assertEqual(results['runners_discovered'], 0)
        self.assertEqual(results['runners_monitored'], 0)
        self.assertEqual(results['metrics_published'], 0)

    @patch.object(lambda_function.ECSRunnerSaturationMonitor, 'discover_runner_services')
    @patch.object(lambda_function.ECSRunnerSaturationMonitor, 'fetch_runner_metrics')
    def test_monitor_all_runners_with_errors(self, mock_fetch, mock_discover):
        """Test monitoring with some failures"""
        # Mock discovered runners
        mock_discover.return_value = [
            {'agent_id': 'agent1'},
            {'agent_id': 'agent2'}
        ]
        
        # Mock one success, one failure
        mock_fetch.side_effect = [
            {'activeTaskCount': 5},  # Success
            None  # Failure
        ]
        
        results = self.monitor.monitor_all_runners()
        
        self.assertEqual(results['runners_discovered'], 2)
        self.assertEqual(results['runners_monitored'], 1)  # Only one successful
        self.assertEqual(len(results['errors']), 0)  # fetch_runner_metrics returning None is not an error


class TestLambdaHandler(unittest.TestCase):
    """Test the Lambda handler function"""

    @patch('lambda_function.ECSRunnerSaturationMonitor')
    def test_lambda_handler_success(self, mock_monitor_class):
        """Test successful Lambda handler execution"""
        # Mock monitor instance
        mock_monitor = Mock()
        mock_monitor.monitor_all_runners.return_value = {
            'runners_discovered': 3,
            'runners_monitored': 3,
            'metrics_published': 12,
            'errors': []
        }
        mock_monitor_class.return_value = mock_monitor
        
        # Call handler
        event = {}
        context = Mock()
        
        response = lambda_function.lambda_handler(event, context)
        
        # Verify response
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])
        self.assertEqual(body['message'], 'Runner monitoring completed successfully')
        self.assertEqual(body['results']['runners_monitored'], 3)

    @patch('lambda_function.ECSRunnerSaturationMonitor')
    def test_lambda_handler_failure(self, mock_monitor_class):
        """Test Lambda handler with exception"""
        # Mock monitor to raise exception
        mock_monitor_class.side_effect = Exception("Test error")
        
        # Call handler
        event = {}
        context = Mock()
        
        response = lambda_function.lambda_handler(event, context)
        
        # Verify error response
        self.assertEqual(response['statusCode'], 500)
        body = json.loads(response['body'])
        self.assertEqual(body['message'], 'Runner monitoring failed')
        self.assertIn('Test error', body['error'])


if __name__ == '__main__':
    # Run tests
    unittest.main(verbosity=2)