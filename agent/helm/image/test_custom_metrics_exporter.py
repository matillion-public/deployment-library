import pytest
import json
import responses
import requests
import time
import signal
import threading
from unittest.mock import patch, MagicMock, Mock
from custom_metics_exporter import (
    app, create_app, fetch_metrics, convert_to_prometheus, signal_handler, wait_for_agent_drain,
    CircuitBreaker, circuit_breaker, healthcheck_failures, last_successful_metrics, last_metrics_time
)


@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client


@pytest.fixture
def sample_metrics():
    return {
        "buildInfo": {
            "version": "1.2.3",
            "commitHash": "abc123",
            "buildTimestamp": "1234567890"
        },
        "agentStatus": "RUNNING",
        "activeTaskCount": 5,
        "activeRequestCount": 3,
        "openSessionsCount": 2
    }


class TestFetchMetrics:
    @patch('custom_metics_exporter.requests.get')
    def test_fetch_metrics_success(self, mock_get, sample_metrics):
        mock_response = Mock()
        mock_response.json.return_value = sample_metrics
        mock_response.raise_for_status.return_value = None
        mock_get.return_value = mock_response
        
        result = fetch_metrics()
        assert result == sample_metrics

    @patch('custom_metics_exporter.MAX_RETRY_ATTEMPTS', 3)
    @patch('custom_metics_exporter.RETRY_DELAY', 0.1)
    @patch('custom_metics_exporter.fetch_metrics_with_circuit_breaker')
    def test_fetch_metrics_failure(self, mock_fetch_cb):
        import custom_metics_exporter
        
        # Reset cache to force fresh fetch
        custom_metics_exporter.last_successful_metrics = None
        custom_metics_exporter.last_metrics_time = None
        custom_metics_exporter.healthcheck_failures['fetch'] = 0
        
        mock_fetch_cb.side_effect = Exception("Connection failed")
        
        with pytest.raises(Exception):
            fetch_metrics()


class TestConvertToPrometheus:
    def test_convert_to_prometheus_full_data(self, sample_metrics):
        result = convert_to_prometheus(sample_metrics)
        
        assert 'app_version_info' in result
        assert 'version="1.2.3"' in result
        assert 'commit_hash="abc123"' in result
        assert 'build_timestamp="1234567890"' in result
        assert 'app_agent_status 1' in result
        assert 'app_active_task_count 5' in result
        assert 'app_active_request_count 3' in result
        assert 'app_open_sessions_count 2' in result

    def test_convert_to_prometheus_empty_data(self):
        empty_metrics = {}
        result = convert_to_prometheus(empty_metrics)
        
        assert 'version="unknown"' in result
        assert 'commit_hash="unknown"' in result
        assert 'build_timestamp="0"' in result
        assert 'app_agent_status 0' in result
        assert 'app_active_task_count 0' in result
        assert 'app_active_request_count 0' in result
        assert 'app_open_sessions_count 0' in result

    def test_convert_to_prometheus_agent_not_running(self):
        metrics = {"agentStatus": "STOPPED"}
        result = convert_to_prometheus(metrics)
        
        assert 'app_agent_status 0' in result

    def test_convert_to_prometheus_partial_build_info(self):
        metrics = {
            "buildInfo": {
                "version": "2.0.0"
                # Missing commitHash and buildTimestamp
            }
        }
        result = convert_to_prometheus(metrics)
        
        assert 'version="2.0.0"' in result
        assert 'commit_hash="unknown"' in result
        assert 'build_timestamp="0"' in result


class TestMetricsEndpoint:
    @responses.activate
    def test_metrics_endpoint_success(self, client, sample_metrics):
        responses.add(
            responses.GET,
            'http://localhost:8080/actuator/info',
            json=sample_metrics,
            status=200
        )
        
        response = client.get('/metrics')
        
        assert response.status_code == 200
        assert response.content_type == 'text/plain; charset=utf-8'
        assert b'app_version_info' in response.data
        assert b'app_agent_status 1' in response.data

    def test_metrics_endpoint_failure(self, client):
        import custom_metics_exporter
        
        # Reset cache to ensure fresh failure
        custom_metics_exporter.last_successful_metrics = None
        custom_metics_exporter.last_metrics_time = None
        custom_metics_exporter.healthcheck_failures['fetch'] = 0
        
        with patch('custom_metics_exporter.fetch_metrics') as mock_fetch:
            mock_fetch.side_effect = Exception("Connection failed")
            
            response = client.get('/metrics')
            
            # Should return 200 with minimal metrics on error (graceful degradation)
            assert response.status_code == 200
            assert b'app_active_task_count 0' in response.data
            assert b'app_active_request_count 0' in response.data
            assert b'app_agent_status 0' in response.data

    def test_metrics_endpoint_content_type(self, client):
        with patch('custom_metics_exporter.fetch_metrics') as mock_fetch:
            mock_fetch.return_value = {}
            
            response = client.get('/metrics')
            
            assert response.content_type == 'text/plain; charset=utf-8'

    def test_prometheus_format_validation(self, client, sample_metrics):
        with patch('custom_metics_exporter.fetch_metrics') as mock_fetch:
            mock_fetch.return_value = sample_metrics
            
            response = client.get('/metrics')
            content = response.data.decode('utf-8')
            
            # Check Prometheus format requirements
            lines = content.split('\n')
            help_lines = [line for line in lines if line.startswith('# HELP')]
            type_lines = [line for line in lines if line.startswith('# TYPE')]
            
            assert len(help_lines) == 5  # One for each metric
            assert len(type_lines) == 5  # One for each metric
            
            # Check that each metric has both HELP and TYPE
            expected_metrics = [
                'app_version_info',
                'app_agent_status', 
                'app_active_task_count',
                'app_active_request_count',
                'app_open_sessions_count'
            ]
            
            for metric in expected_metrics:
                assert f'# HELP {metric}' in content
                assert f'# TYPE {metric} gauge' in content


class TestHealthEndpoint:
    def test_health_endpoint_success(self, client):
        """Test the new health endpoint"""
        response = client.get('/health')
        assert response.status_code == 200
        assert b'OK' in response.data
    
    def test_health_endpoint_too_many_failures(self, client):
        """Test health endpoint with too many failures"""
        import custom_metics_exporter
        original_failures = custom_metics_exporter.healthcheck_failures['fetch']
        custom_metics_exporter.healthcheck_failures['fetch'] = 15
        
        try:
            response = client.get('/health')
            assert response.status_code == 503
            assert b'Too many fetch failures' in response.data
        finally:
            custom_metics_exporter.healthcheck_failures['fetch'] = original_failures
    
    def test_health_endpoint_during_shutdown(self, client):
        """Test health endpoint during shutdown"""
        import custom_metics_exporter
        custom_metics_exporter.shutdown_event.set()
        
        try:
            response = client.get('/health')
            assert response.status_code == 503
            assert b'Shutting down' in response.data
        finally:
            custom_metics_exporter.shutdown_event.clear()

class TestAppConfiguration:
    def test_app_runs(self):
        """Test that the Flask app can be created and configured"""
        assert app is not None
        assert app.config.get('TESTING') is not None


class TestErrorHandling:
    @patch('custom_metics_exporter.logger')
    def test_logging_on_error(self, mock_logger, client):
        with patch('custom_metics_exporter.fetch_metrics') as mock_fetch:
            mock_fetch.side_effect = Exception("Connection failed")
            
            response = client.get('/metrics')
            
            mock_logger.error.assert_called_once()
            # Should return 200 with minimal metrics (graceful degradation)
            assert response.status_code == 200


class TestSignalHandling:
    @patch('custom_metics_exporter.wait_for_agent_drain')
    @patch('custom_metics_exporter.sys.exit')
    def test_signal_handler_sigterm(self, mock_exit, mock_wait):
        mock_frame = Mock()
        
        signal_handler(signal.SIGTERM, mock_frame)
        
        mock_wait.assert_called_once()
        mock_exit.assert_called_once_with(0)

    @patch('custom_metics_exporter.wait_for_agent_drain')
    @patch('custom_metics_exporter.sys.exit')
    def test_signal_handler_sigint(self, mock_exit, mock_wait):
        mock_frame = Mock()
        
        signal_handler(signal.SIGINT, mock_frame)
        
        mock_wait.assert_called_once()
        mock_exit.assert_called_once_with(0)


class TestAgentDrainWait:
    def test_wait_for_agent_drain_agent_stops_responding(self):
        import custom_metics_exporter
        
        # Mock the requests module directly on the imported module
        with patch.object(custom_metics_exporter.requests, 'get') as mock_get:
            # Agent responds once then fails
            mock_get.side_effect = [
                Mock(status_code=200),  # First call succeeds
                requests.exceptions.RequestException("Connection failed")  # Second call fails
            ]
            
            # Override grace period for fast test
            original_grace = custom_metics_exporter.GRACE_PERIOD_SECONDS
            custom_metics_exporter.GRACE_PERIOD_SECONDS = 2
            
            try:
                start_time = time.time()
                wait_for_agent_drain()
                end_time = time.time()
                
                # Should exit quickly when agent stops responding
                assert end_time - start_time < 2
                assert mock_get.call_count == 2
            finally:
                custom_metics_exporter.GRACE_PERIOD_SECONDS = original_grace

    def test_wait_for_agent_drain_grace_period_expires(self):
        import custom_metics_exporter
        
        # Mock the requests module directly on the imported module
        with patch.object(custom_metics_exporter.requests, 'get') as mock_get:
            # Agent keeps responding
            mock_get.return_value = Mock(status_code=200)
            
            # Override grace period for fast test
            original_grace = custom_metics_exporter.GRACE_PERIOD_SECONDS
            custom_metics_exporter.GRACE_PERIOD_SECONDS = 1
            
            try:
                start_time = time.time()
                wait_for_agent_drain()
                end_time = time.time()
                
                # Should wait for full grace period
                assert end_time - start_time >= 1
            finally:
                custom_metics_exporter.GRACE_PERIOD_SECONDS = original_grace


class TestAgentDrainingState:
    def test_fetch_metrics_during_drain_reduces_retries(self):
        import custom_metics_exporter
        
        # Mock the circuit breaker fetch function
        with patch('custom_metics_exporter.fetch_metrics_with_circuit_breaker') as mock_fetch_cb:
            # Mock circuit breaker to always fail
            mock_fetch_cb.side_effect = requests.exceptions.RequestException("Connection failed")
            
            # Override module variables
            original_draining = custom_metics_exporter.agent_draining
            original_retry = custom_metics_exporter.RETRY_DELAY
            
            # Reset cache to force fresh fetch
            custom_metics_exporter.last_successful_metrics = None
            custom_metics_exporter.last_metrics_time = None
            custom_metics_exporter.healthcheck_failures['fetch'] = 0
            
            custom_metics_exporter.agent_draining = True
            custom_metics_exporter.RETRY_DELAY = 0.1
            custom_metics_exporter.shutdown_event.clear()
            
            try:
                with pytest.raises(requests.exceptions.RequestException):
                    fetch_metrics()
                
                # Should have made exactly 3 requests (reduced from 30)
                assert mock_fetch_cb.call_count == 3
            finally:
                custom_metics_exporter.agent_draining = original_draining
                custom_metics_exporter.RETRY_DELAY = original_retry

    def test_fetch_metrics_normal_state_full_retries(self):
        import custom_metics_exporter
        
        # Mock the circuit breaker fetch function
        with patch('custom_metics_exporter.fetch_metrics_with_circuit_breaker') as mock_fetch_cb:
            # Mock circuit breaker to always fail
            mock_fetch_cb.side_effect = requests.exceptions.RequestException("Connection failed")
            
            # Override module variables for faster test
            original_draining = custom_metics_exporter.agent_draining
            original_attempts = custom_metics_exporter.MAX_RETRY_ATTEMPTS
            original_delay = custom_metics_exporter.RETRY_DELAY
            
            # Reset cache to force fresh fetch
            custom_metics_exporter.last_successful_metrics = None
            custom_metics_exporter.last_metrics_time = None
            custom_metics_exporter.healthcheck_failures['fetch'] = 0
            
            custom_metics_exporter.agent_draining = False
            custom_metics_exporter.MAX_RETRY_ATTEMPTS = 5  # Reduce for faster tests
            custom_metics_exporter.RETRY_DELAY = 0.1
            custom_metics_exporter.shutdown_event.clear()
            
            try:
                with pytest.raises(requests.exceptions.RequestException):
                    fetch_metrics()
                
                # Should have made 5 requests (full amount when not draining)
                assert mock_fetch_cb.call_count == 5
            finally:
                custom_metics_exporter.agent_draining = original_draining
                custom_metics_exporter.MAX_RETRY_ATTEMPTS = original_attempts
                custom_metics_exporter.RETRY_DELAY = original_delay


class TestCircuitBreaker:
    def test_circuit_breaker_closed_state(self):
        """Test circuit breaker in closed state"""
        cb = CircuitBreaker(failure_threshold=3, recovery_timeout=1)
        
        def mock_func():
            return "success"
        
        result = cb.call(mock_func)
        assert result == "success"
        assert cb.state == 'CLOSED'
    
    def test_circuit_breaker_opens_after_failures(self):
        """Test circuit breaker opens after threshold failures"""
        cb = CircuitBreaker(failure_threshold=3, recovery_timeout=1)
        
        def failing_func():
            raise Exception("Function failed")
        
        # Fail 3 times to trip the breaker
        for _ in range(3):
            try:
                cb.call(failing_func)
            except Exception:
                pass
        
        assert cb.state == 'OPEN'
        assert cb.failure_count == 3
    
    def test_circuit_breaker_half_open_recovery(self):
        """Test circuit breaker recovery to half-open state"""
        cb = CircuitBreaker(failure_threshold=2, recovery_timeout=0.1)
        
        def failing_func():
            raise Exception("Function failed")
        
        def success_func():
            return "recovered"
        
        # Trip the breaker
        for _ in range(2):
            try:
                cb.call(failing_func)
            except Exception:
                pass
        
        assert cb.state == 'OPEN'
        
        # Wait for recovery timeout
        time.sleep(0.2)
        
        # Should transition to half-open and then closed on success
        result = cb.call(success_func)
        assert result == "recovered"
        assert cb.state == 'CLOSED'
        assert cb.failure_count == 0


class TestMetricsCaching:
    def test_metrics_caching_success(self):
        """Test metrics caching functionality"""
        import custom_metics_exporter
        
        # Reset cache
        custom_metics_exporter.last_successful_metrics = None
        custom_metics_exporter.last_metrics_time = None
        
        sample_metrics = {"activeTaskCount": 5}
        
        with patch('custom_metics_exporter.fetch_metrics_with_circuit_breaker') as mock_fetch:
            mock_fetch.return_value = sample_metrics
            
            # First call should fetch from source
            result1 = fetch_metrics()
            assert result1 == sample_metrics
            assert mock_fetch.call_count == 1
            
            # Second call within TTL should use cache
            result2 = fetch_metrics()
            assert result2 == sample_metrics
            assert mock_fetch.call_count == 1  # No additional call
    
    def test_metrics_cache_expiry(self):
        """Test metrics cache expiry"""
        import custom_metics_exporter
        
        # Reset cache
        custom_metics_exporter.last_successful_metrics = {"activeTaskCount": 3}
        custom_metics_exporter.last_metrics_time = time.time() - 40  # Expired
        
        sample_metrics = {"activeTaskCount": 7}
        
        with patch('custom_metics_exporter.fetch_metrics_with_circuit_breaker') as mock_fetch:
            mock_fetch.return_value = sample_metrics
            
            result = fetch_metrics()
            assert result == sample_metrics
            assert mock_fetch.call_count == 1  # Should fetch fresh data
    
    def test_stale_cache_on_repeated_failures(self):
        """Test returning stale cache data on repeated failures"""
        import custom_metics_exporter
        
        # Set up stale cache
        stale_metrics = {"activeTaskCount": 2}
        custom_metics_exporter.last_successful_metrics = stale_metrics
        custom_metics_exporter.last_metrics_time = time.time() - 40  # Expired
        custom_metics_exporter.healthcheck_failures['fetch'] = 5  # Many failures
        custom_metics_exporter.agent_draining = False
        custom_metics_exporter.MAX_RETRY_ATTEMPTS = 2
        
        try:
            with patch('custom_metics_exporter.fetch_metrics_with_circuit_breaker') as mock_fetch:
                mock_fetch.side_effect = Exception("Connection failed")
                
                result = fetch_metrics()
                assert result == stale_metrics  # Should return stale data
        finally:
            custom_metics_exporter.healthcheck_failures['fetch'] = 0