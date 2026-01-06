# Testing the ECS Agent Saturation Monitor Lambda Function

This directory contains comprehensive unit and integration tests for the Lambda function.

## Test Structure

### Unit Tests (`test_lambda_function.py`)
- **Service Discovery**: Tests agent service identification logic
- **Agent ID Extraction**: Tests extracting agent IDs from task definitions
- **Private IP Extraction**: Tests getting private IPs from ECS tasks
- **Metrics Fetching**: Tests HTTP requests to actuator endpoints
- **CloudWatch Publishing**: Tests metric publishing to CloudWatch
- **Complete Workflow**: Tests end-to-end monitoring process
- **Lambda Handler**: Tests the main Lambda entry point

### Integration Tests (`test_integration.py`)
- **Mocked AWS Services**: Tests with moto-mocked AWS services
- **Service Discovery**: Tests real ECS service discovery logic
- **Real Environment**: Optional tests against actual AWS (use carefully)

### Test Configuration
- **`conftest.py`**: Shared fixtures and test setup
- **`pytest.ini`**: PyTest configuration and coverage settings
- **`test_requirements.txt`**: Test-only dependencies

## Running Tests

### Quick Start
```bash
# Make the test runner executable and run all tests
chmod +x run_tests.sh
./run_tests.sh
```

### Manual Test Execution

#### 1. Set up test environment
```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install test dependencies
pip install -r test_requirements.txt
```

#### 2. Run unit tests
```bash
# Run all unit tests with coverage
pytest test_lambda_function.py -v --cov=lambda_function --cov-report=html

# Run with unittest (alternative)
python -m unittest test_lambda_function.py -v

# Run specific test class
pytest test_lambda_function.py::TestECSAgentSaturationMonitor -v

# Run specific test method
pytest test_lambda_function.py::TestECSAgentSaturationMonitor::test_is_agent_service_default_indicators -v
```

#### 3. Run integration tests
```bash
# Run integration tests (uses moto for AWS mocking)
pytest test_integration.py -m integration -v

# Run slow tests (includes real AWS tests)
pytest test_integration.py -m slow -v
```

#### 4. View coverage report
```bash
# Generate and view HTML coverage report
pytest --cov=lambda_function --cov-report=html
open htmlcov/index.html  # macOS
# or
xdg-open htmlcov/index.html  # Linux
```

## Test Cases Covered

### ✅ Service Discovery
- [x] Default service indicators (`matillion`, `agent`, `dpc`)
- [x] Custom service indicators from environment variables
- [x] Case-insensitive matching
- [x] Non-matching service names

### ✅ Agent Information Extraction
- [x] Agent ID from task definition environment variables
- [x] Agent ID fallback to task ID
- [x] Private IP from ECS task attachments
- [x] Missing private IP handling

### ✅ Metrics Fetching
- [x] Successful HTTP requests to actuator endpoints
- [x] Multiple endpoint attempts (8080, 8000, different paths)
- [x] HTTP connection failures
- [x] JSON parsing errors
- [x] Missing private IP scenarios

### ✅ CloudWatch Publishing
- [x] Metric data formatting and dimensions
- [x] Agent status value conversion (RUNNING=1, other=0)
- [x] Multiple metrics per agent
- [x] CloudWatch API call verification

### ✅ Complete Workflow
- [x] End-to-end monitoring process
- [x] Multiple agent discovery and monitoring
- [x] Error handling and recovery
- [x] Results aggregation and reporting

### ✅ Lambda Handler
- [x] Successful execution and response formatting
- [x] Exception handling and error responses
- [x] Lambda context usage

### ✅ Integration Testing
- [x] Mocked AWS service interactions
- [x] ECS cluster, service, and task creation
- [x] CloudWatch metric publishing
- [x] Service discovery with real AWS data structures

## Test Configuration Options

### Environment Variables for Testing
```bash
# Override default service indicators
export AGENT_SERVICE_INDICATORS="custom-agent,worker,processor"

# Set test CloudWatch namespace
export CLOUDWATCH_NAMESPACE="Test/AgentSaturation"

# Enable debug logging
export LOG_LEVEL="DEBUG"
```

### Pytest Markers
```bash
# Run only unit tests
pytest -m "unit" -v

# Run only integration tests
pytest -m "integration" -v

# Run only slow tests
pytest -m "slow" -v

# Skip slow tests
pytest -m "not slow" -v
```

## Mock Data

The tests use realistic mock data that matches actual AWS API responses:

- **ECS Tasks**: Complete task definitions with network attachments
- **ECS Services**: Service configurations with proper ARNs
- **Agent Metrics**: Sample actuator endpoint responses
- **CloudWatch**: Metric data with proper dimensions and values

## Troubleshooting Tests

### Common Issues

1. **Import Errors**
   ```bash
   # Ensure you're in the correct directory
   cd modules/aws/lambda/saturation-monitor
   
   # Check Python path
   export PYTHONPATH="${PYTHONPATH}:$(pwd)"
   ```

2. **AWS Credential Warnings**
   ```bash
   # Tests use mocked credentials - warnings are normal
   # For real AWS tests, set up credentials:
   aws configure
   # or
   export AWS_ACCESS_KEY_ID=your_key
   export AWS_SECRET_ACCESS_KEY=your_secret
   ```

3. **Coverage Too Low**
   ```bash
   # Current coverage requirement is 80%
   # Run with detailed coverage to see missing lines:
   pytest --cov=lambda_function --cov-report=term-missing
   ```

### Debugging Failing Tests
```bash
# Run with verbose output and stop on first failure
pytest -v -x

# Run with Python debugger on failures
pytest --pdb

# Show print statements and logging
pytest -s
```

## Continuous Integration

These tests are designed to run in CI/CD pipelines:

```yaml
# Example GitHub Actions step
- name: Run Lambda Tests
  run: |
    cd modules/aws/lambda/saturation-monitor
    pip install -r test_requirements.txt
    pytest test_lambda_function.py --cov=lambda_function --cov-fail-under=80
```

## Test Data Files

Test fixtures provide:
- Sample ECS task and service configurations
- Realistic actuator endpoint responses
- CloudWatch metric data structures
- Lambda context objects

All test data is self-contained and doesn't require external dependencies.