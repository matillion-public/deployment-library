"""
PyTest configuration and shared fixtures for Lambda function tests
"""

import pytest
import os
from unittest.mock import Mock


@pytest.fixture
def mock_aws_credentials():
    """Mock AWS credentials for testing"""
    os.environ.setdefault('AWS_ACCESS_KEY_ID', 'testing')
    os.environ.setdefault('AWS_SECRET_ACCESS_KEY', 'testing')
    os.environ.setdefault('AWS_SECURITY_TOKEN', 'testing')
    os.environ.setdefault('AWS_SESSION_TOKEN', 'testing')
    os.environ.setdefault('AWS_DEFAULT_REGION', 'us-east-1')


@pytest.fixture
def mock_lambda_context():
    """Mock Lambda context object"""
    context = Mock()
    context.function_name = 'test-saturation-monitor'
    context.function_version = '$LATEST'
    context.invoked_function_arn = 'arn:aws:lambda:us-east-1:123456789012:function:test-saturation-monitor'
    context.memory_limit_in_mb = 256
    context.remaining_time_in_millis = lambda: 30000
    context.log_group_name = '/aws/lambda/test-saturation-monitor'
    context.log_stream_name = '2024/01/01/[$LATEST]abcdef123456'
    context.aws_request_id = 'test-request-id-123'
    return context


@pytest.fixture
def sample_ecs_task():
    """Sample ECS task data for testing"""
    return {
        'taskArn': 'arn:aws:ecs:us-east-1:123456789012:task/test-cluster/abc123def456',
        'taskDefinitionArn': 'arn:aws:ecs:us-east-1:123456789012:task-definition/test-task:1',
        'clusterArn': 'arn:aws:ecs:us-east-1:123456789012:cluster/test-cluster',
        'lastStatus': 'RUNNING',
        'desiredStatus': 'RUNNING',
        'attachments': [{
            'type': 'ElasticNetworkInterface',
            'status': 'ATTACHED',
            'details': [
                {'name': 'networkInterfaceId', 'value': 'eni-12345678'},
                {'name': 'privateIPv4Address', 'value': '10.0.1.100'},
                {'name': 'subnetId', 'value': 'subnet-12345678'}
            ]
        }]
    }


@pytest.fixture
def sample_ecs_service():
    """Sample ECS service data for testing"""
    return {
        'serviceName': 'matillion-agent-service',
        'serviceArn': 'arn:aws:ecs:us-east-1:123456789012:service/test-cluster/matillion-agent-service',
        'clusterArn': 'arn:aws:ecs:us-east-1:123456789012:cluster/test-cluster',
        'status': 'ACTIVE',
        'runningCount': 1,
        'pendingCount': 0,
        'desiredCount': 1
    }


@pytest.fixture
def sample_metrics_data():
    """Sample metrics data from agent actuator endpoint"""
    return {
        'activeTaskCount': 15,
        'activeRequestCount': 8,
        'openSessionsCount': 25,
        'agentStatus': 'RUNNING',
        'buildInfo': {
            'version': '1.0.0',
            'commitHash': 'abc123',
            'buildTimestamp': 1234567890
        }
    }


@pytest.fixture(autouse=True)
def setup_test_environment(mock_aws_credentials):
    """Automatically set up test environment for all tests"""
    # Set test environment variables
    test_env = {
        'CLOUDWATCH_NAMESPACE': 'Test/AgentSaturation',
        'LOG_LEVEL': 'DEBUG',
        'AGENT_SERVICE_INDICATORS': 'test-agent,matillion'
    }
    
    original_env = {}
    for key, value in test_env.items():
        original_env[key] = os.environ.get(key)
        os.environ[key] = value
    
    yield
    
    # Restore original environment
    for key, value in original_env.items():
        if value is None:
            os.environ.pop(key, None)
        else:
            os.environ[key] = value