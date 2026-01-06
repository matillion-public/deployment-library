#!/usr/bin/env python3
"""
Integration tests for the metrics exporter endpoint
These tests require a running instance of the metrics exporter
"""
import requests
import pytest
import time
import re

class TestMetricsEndpointIntegration:
    
    @pytest.fixture
    def metrics_url(self):
        """Base URL for the metrics endpoint"""
        return "http://localhost:8000"
    
    def test_metrics_endpoint_accessibility(self, metrics_url):
        """Test that the /metrics endpoint is accessible"""
        try:
            response = requests.get(f"{metrics_url}/metrics", timeout=5)
            assert response.status_code == 200
        except requests.exceptions.RequestException:
            pytest.skip("Metrics exporter not running - skipping integration test")
    
    def test_prometheus_format_compliance(self, metrics_url):
        """Test that the output follows Prometheus format"""
        try:
            response = requests.get(f"{metrics_url}/metrics", timeout=5)
            content = response.text
            
            # Check content type
            assert response.headers.get('content-type', '').startswith('text/plain')
            
            # Check for required Prometheus format elements
            lines = content.split('\n')
            
            # Should have HELP and TYPE comments
            help_lines = [line for line in lines if line.startswith('# HELP')]
            type_lines = [line for line in lines if line.startswith('# TYPE')]
            
            assert len(help_lines) > 0, "No HELP lines found"
            assert len(type_lines) > 0, "No TYPE lines found"
            
            # Check metric names follow Prometheus naming conventions
            metric_lines = [line for line in lines if line and not line.startswith('#')]
            
            for line in metric_lines:
                if ' ' in line:
                    metric_name = line.split(' ')[0].split('{')[0]
                    assert re.match(r'^[a-zA-Z_:][a-zA-Z0-9_:]*$', metric_name), \
                        f"Invalid metric name: {metric_name}"
        
        except requests.exceptions.RequestException:
            pytest.skip("Metrics exporter not running - skipping integration test")
    
    def test_expected_metrics_present(self, metrics_url):
        """Test that all expected metrics are present"""
        expected_metrics = [
            'app_version_info',
            'app_agent_status',
            'app_active_task_count',
            'app_active_request_count',
            'app_open_sessions_count'
        ]
        
        try:
            response = requests.get(f"{metrics_url}/metrics", timeout=5)
            content = response.text
            
            for metric in expected_metrics:
                assert f"# HELP {metric}" in content, f"Missing HELP for {metric}"
                assert f"# TYPE {metric} gauge" in content, f"Missing TYPE for {metric}"
                assert metric in content, f"Missing metric data for {metric}"
        
        except requests.exceptions.RequestException:
            pytest.skip("Metrics exporter not running - skipping integration test")
    
    def test_metric_values_are_valid(self, metrics_url):
        """Test that metric values are valid numbers"""
        try:
            response = requests.get(f"{metrics_url}/metrics", timeout=5)
            content = response.text
            
            lines = content.split('\n')
            metric_lines = [line for line in lines if line and not line.startswith('#')]
            
            for line in metric_lines:
                if ' ' in line:
                    parts = line.split(' ')
                    if len(parts) >= 2:
                        try:
                            value = float(parts[-1])
                            assert value >= 0, f"Negative value found: {value} in line: {line}"
                        except ValueError:
                            pytest.fail(f"Invalid numeric value in line: {line}")
        
        except requests.exceptions.RequestException:
            pytest.skip("Metrics exporter not running - skipping integration test")
    
    def test_response_time(self, metrics_url):
        """Test that the metrics endpoint responds within acceptable time"""
        try:
            start_time = time.time()
            response = requests.get(f"{metrics_url}/metrics", timeout=5)
            response_time = time.time() - start_time
            
            assert response.status_code == 200
            assert response_time < 2.0, f"Response time too slow: {response_time}s"
        
        except requests.exceptions.RequestException:
            pytest.skip("Metrics exporter not running - skipping integration test")
    
    def test_multiple_requests_consistency(self, metrics_url):
        """Test that multiple requests return consistent format"""
        try:
            responses = []
            for _ in range(3):
                response = requests.get(f"{metrics_url}/metrics", timeout=5)
                assert response.status_code == 200
                responses.append(response.text)
                time.sleep(0.1)
            
            # All responses should have same metric names (values may differ)
            first_lines = set(line.split(' ')[0].split('{')[0] 
                            for line in responses[0].split('\n') 
                            if line and not line.startswith('#') and ' ' in line)
            
            for response_text in responses[1:]:
                current_lines = set(line.split(' ')[0].split('{')[0] 
                                  for line in response_text.split('\n') 
                                  if line and not line.startswith('#') and ' ' in line)
                assert first_lines == current_lines, "Inconsistent metric names across requests"
        
        except requests.exceptions.RequestException:
            pytest.skip("Metrics exporter not running - skipping integration test")