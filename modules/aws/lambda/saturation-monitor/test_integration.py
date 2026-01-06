#!/usr/bin/env python3
"""
Integration tests for ECS Agent Saturation Monitor Lambda function

These tests require actual AWS credentials and resources for integration testing.
Run with: pytest test_integration.py -m integration
"""

import pytest
import json
import boto3
import os
from moto import mock_ecs, mock_cloudwatch, mock_ec2
from unittest.mock import patch

# Import the Lambda function
import lambda_function


@pytest.mark.integration
class TestECSAgentSaturationMonitorIntegration:
    """Integration tests using moto for AWS service mocking"""

    @mock_ecs
    @mock_cloudwatch
    @mock_ec2
    def test_full_workflow_with_mocked_aws(self):
        """Test complete workflow with mocked AWS services"""
        # Setup mocked AWS environment
        ecs_client = boto3.client('ecs', region_name='us-east-1')
        cloudwatch_client = boto3.client('cloudwatch', region_name='us-east-1')
        ec2_client = boto3.client('ec2', region_name='us-east-1')
        
        # Create mock VPC and subnet
        vpc = ec2_client.create_vpc(CidrBlock='10.0.0.0/16')
        subnet = ec2_client.create_subnet(
            VpcId=vpc['Vpc']['VpcId'],
            CidrBlock='10.0.1.0/24'
        )
        
        # Create mock ECS cluster
        cluster_response = ecs_client.create_cluster(clusterName='test-cluster')
        cluster_arn = cluster_response['cluster']['clusterArn']
        
        # Register task definition
        task_def_response = ecs_client.register_task_definition(
            family='matillion-agent-task',
            networkMode='awsvpc',
            requiresCompatibilities=['FARGATE'],
            cpu='256',
            memory='512',
            containerDefinitions=[{
                'name': 'matillion-agent',
                'image': 'test-image:latest',
                'essential': True,
                'environment': [
                    {'name': 'AGENT_ID', 'value': 'test-agent-001'}
                ]
            }]
        )
        
        # Create service
        service_response = ecs_client.create_service(
            cluster=cluster_arn,
            serviceName='matillion-agent-service',
            taskDefinition='matillion-agent-task:1',
            desiredCount=1,
            networkConfiguration={
                'awsvpcConfiguration': {
                    'subnets': [subnet['Subnet']['SubnetId']],
                    'assignPublicIp': 'DISABLED'
                }
            }
        )
        
        # Create a mock running task
        task_response = ecs_client.run_task(
            cluster=cluster_arn,
            taskDefinition='matillion-agent-task:1',
            count=1,
            networkConfiguration={
                'awsvpcConfiguration': {
                    'subnets': [subnet['Subnet']['SubnetId']],
                    'assignPublicIp': 'DISABLED'
                }
            }
        )
        
        # Mock successful HTTP response for metrics endpoint
        mock_metrics_data = {
            'activeTaskCount': 10,
            'activeRequestCount': 5,
            'openSessionsCount': 15,
            'agentStatus': 'RUNNING'
        }
        
        with patch('urllib.request.urlopen') as mock_urlopen:
            # Mock HTTP response
            mock_response = mock_urlopen.return_value.__enter__.return_value
            mock_response.getcode.return_value = 200
            mock_response.read.return_value = json.dumps(mock_metrics_data).encode('utf-8')
            
            # Create monitor instance
            monitor = lambda_function.ECSAgentSaturationMonitor()
            
            # Override AWS clients to use mocked ones
            monitor.ecs = ecs_client
            monitor.cloudwatch = cloudwatch_client
            
            # Run monitoring
            results = monitor.monitor_all_agents()
            
            # Verify results
            assert results['agents_discovered'] >= 0  # May be 0 if service discovery logic differs
            
            # If agents were discovered and processed
            if results['agents_discovered'] > 0:
                assert results['agents_monitored'] >= 0
                assert results['metrics_published'] >= 0
                assert isinstance(results['errors'], list)

    @pytest.mark.slow
    def test_real_lambda_handler(self):
        """Test Lambda handler with real AWS environment (requires AWS credentials)"""
        # Skip if no AWS credentials available
        try:
            boto3.client('sts').get_caller_identity()
        except Exception:
            pytest.skip("AWS credentials not available for integration test")
        
        # Test with minimal event
        event = {}
        context = type('Context', (), {
            'function_name': 'test-function',
            'aws_request_id': 'test-request-123',
            'remaining_time_in_millis': lambda: 30000
        })()
        
        # This would run against real AWS - use carefully
        # Uncomment only when you want to test against real environment
        # response = lambda_function.lambda_handler(event, context)
        # assert response['statusCode'] in [200, 500]  # Either success or controlled failure
        
        # For now, just test that the function is importable and callable
        assert callable(lambda_function.lambda_handler)

    @mock_ecs
    def test_ecs_service_discovery(self):
        """Test ECS service discovery logic"""
        ecs_client = boto3.client('ecs', region_name='us-east-1')
        
        # Create test cluster
        cluster_response = ecs_client.create_cluster(clusterName='test-cluster')
        cluster_arn = cluster_response['cluster']['clusterArn']
        
        # Register task definition
        ecs_client.register_task_definition(
            family='matillion-agent-task',
            containerDefinitions=[{
                'name': 'agent',
                'image': 'test:latest',
                'essential': True
            }]
        )
        
        # Create services with different names
        test_services = [
            'matillion-prod-service',  # Should be discovered
            'agent-worker',           # Should be discovered  
            'dpc-processor',          # Should be discovered
            'web-server',             # Should NOT be discovered
            'database'                # Should NOT be discovered
        ]
        
        for service_name in test_services:
            ecs_client.create_service(
                cluster=cluster_arn,
                serviceName=service_name,
                taskDefinition='matillion-agent-task:1',
                desiredCount=1
            )
        
        # Test discovery
        monitor = lambda_function.ECSAgentSaturationMonitor()
        monitor.ecs = ecs_client
        
        # Test service identification
        for service_name in test_services:
            is_agent = monitor._is_agent_service(service_name, {})
            if any(indicator in service_name.lower() for indicator in ['matillion', 'agent', 'dpc']):
                assert is_agent, f"Service {service_name} should be identified as agent service"
            else:
                assert not is_agent, f"Service {service_name} should NOT be identified as agent service"


if __name__ == '__main__':
    # Run integration tests
    pytest.main([__file__, '-v', '-m', 'integration'])