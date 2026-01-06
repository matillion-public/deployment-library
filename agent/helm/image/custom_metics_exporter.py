import logging
from flask import Flask, Response
import requests
import os
import time
import signal
import sys
import threading
from collections import defaultdict

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Circuit breaker for resilience
class CircuitBreaker:
    def __init__(self, failure_threshold=5, recovery_timeout=30):
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.failure_count = 0
        self.last_failure_time = None
        self.state = 'CLOSED'  # CLOSED, OPEN, HALF_OPEN
    
    def call(self, func, *args, **kwargs):
        if self.state == 'OPEN':
            if time.time() - self.last_failure_time > self.recovery_timeout:
                self.state = 'HALF_OPEN'
                logger.info("Circuit breaker transitioning to HALF_OPEN")
            else:
                raise Exception("Circuit breaker is OPEN")
        
        try:
            result = func(*args, **kwargs)
            if self.state == 'HALF_OPEN':
                self.state = 'CLOSED'
                self.failure_count = 0
                logger.info("Circuit breaker reset to CLOSED")
            return result
        except Exception as e:
            self.failure_count += 1
            self.last_failure_time = time.time()
            
            if self.failure_count >= self.failure_threshold:
                self.state = 'OPEN'
                logger.error(f"Circuit breaker opened after {self.failure_count} failures")
            raise e

circuit_breaker = CircuitBreaker()

METRICS_ENDPOINT = os.environ.get('METRICS_ENDPOINT', 'http://localhost:8080/actuator/info')
MAX_RETRY_ATTEMPTS = int(os.environ.get('MAX_RETRY_ATTEMPTS', '30'))
RETRY_DELAY = int(os.environ.get('RETRY_DELAY', '5'))
GRACE_PERIOD_SECONDS = int(os.environ.get('GRACE_PERIOD_SECONDS', '43200'))

shutdown_event = threading.Event()
agent_draining = False
last_successful_metrics = None
last_metrics_time = None
metrics_cache_ttl = 30  # Cache metrics for 30 seconds

# Health check state
healthcheck_failures = defaultdict(int)

def signal_handler(signum, frame):
    global agent_draining
    logging.info(f"Received signal {signum}, waiting for agent to complete drain period...")
    agent_draining = True
    
    # Wait for grace period or until agent stops responding
    wait_for_agent_drain()
    
    logging.info("Shutting down metrics exporter")
    shutdown_event.set()
    sys.exit(0)

def wait_for_agent_drain():
    """Wait for agent to finish draining or grace period to expire"""
    start_time = time.time()
    
    while time.time() - start_time < GRACE_PERIOD_SECONDS:
        try:
            # Check if agent is still responding to health checks
            response = requests.get(METRICS_ENDPOINT, timeout=5)
            if response.status_code == 200:
                logging.debug("Agent still active, continuing to serve metrics...")
                time.sleep(1)
            else:
                logging.info("Agent stopped responding, initiating shutdown")
                break
        except requests.exceptions.RequestException:
            logging.info("Agent no longer accessible, initiating shutdown")
            break
    
    logging.info("Grace period completed or agent finished draining")

signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

def fetch_metrics_with_circuit_breaker():
    """Fetch metrics with circuit breaker pattern"""
    return circuit_breaker.call(_fetch_metrics_internal)

def _fetch_metrics_internal():
    """Internal method to fetch metrics from agent"""
    response = requests.get(METRICS_ENDPOINT, timeout=10)
    response.raise_for_status()
    return response.json()

def fetch_metrics():
    global last_successful_metrics, last_metrics_time
    
    # If agent is draining, reduce retry attempts to be more responsive
    max_attempts = 3 if agent_draining else MAX_RETRY_ATTEMPTS
    retry_delay = 1 if agent_draining else RETRY_DELAY
    
    # Check if we have cached metrics that are still valid
    if (last_successful_metrics is not None and 
        last_metrics_time is not None and 
        time.time() - last_metrics_time < metrics_cache_ttl):
        logger.debug("Returning cached metrics")
        return last_successful_metrics
    
    for attempt in range(max_attempts):
        if shutdown_event.is_set():
            raise Exception("Shutdown initiated, stopping metrics fetch")
        try:
            metrics_data = fetch_metrics_with_circuit_breaker()
            
            # Cache successful response
            last_successful_metrics = metrics_data
            last_metrics_time = time.time()
            
            # Reset failure count on success
            healthcheck_failures['fetch'] = 0
            
            return metrics_data
            
        except Exception as e:
            healthcheck_failures['fetch'] += 1
            
            if attempt < max_attempts - 1:
                if not agent_draining:
                    logger.warning(f"Attempt {attempt + 1} failed to fetch metrics: {e}. Retrying in {retry_delay} seconds...")
                if shutdown_event.wait(retry_delay):
                    raise Exception("Shutdown initiated during retry wait")
            else:
                if agent_draining:
                    logger.info("Agent appears to be shutting down, metrics no longer available")
                else:
                    logger.error(f"Failed to fetch metrics after {max_attempts} attempts: {e}")
                
                # If we have cached metrics and too many recent failures, return stale data with warning
                if (last_successful_metrics is not None and 
                    healthcheck_failures['fetch'] >= 3):
                    logger.warning("Returning stale cached metrics due to repeated failures")
                    return last_successful_metrics
                
                raise

def convert_to_prometheus(metrics):
    prom_metrics = []
    build_info = metrics.get("buildInfo", {})
    agent_status = metrics.get("agentStatus", "")

    # Build information
    prom_metrics.append('# HELP app_version_info Application version information.')
    prom_metrics.append('# TYPE app_version_info gauge')
    version = build_info.get("version", "unknown")
    commit_hash = build_info.get("commitHash", "unknown")
    build_timestamp = build_info.get("buildTimestamp", 0)
    prom_metrics.append(f'app_version_info{{version="{version}", commit_hash="{commit_hash}", build_timestamp="{build_timestamp}"}} 1')

    # Agent status
    prom_metrics.append('# HELP app_agent_status Shows if the agent is running. (1 for running, 0 for not)')
    prom_metrics.append('# TYPE app_agent_status gauge')
    agent_status_value = 1 if agent_status == "RUNNING" else 0
    prom_metrics.append(f'app_agent_status {agent_status_value}')

    # Active task count
    prom_metrics.append('# HELP app_active_task_count The number of active tasks.')
    prom_metrics.append('# TYPE app_active_task_count gauge')
    active_task_count = metrics.get("activeTaskCount", 0)
    prom_metrics.append(f'app_active_task_count {active_task_count}')

    # Active request count
    prom_metrics.append('# HELP app_active_request_count The number of active requests.')
    prom_metrics.append('# TYPE app_active_request_count gauge')
    active_request_count = metrics.get("activeRequestCount", 0)
    prom_metrics.append(f'app_active_request_count {active_request_count}')

    # Open sessions count
    prom_metrics.append('# HELP app_open_sessions_count The number of open sessions.')
    prom_metrics.append('# TYPE app_open_sessions_count gauge')
    open_sessions_count = metrics.get("openSessionsCount", 0)
    prom_metrics.append(f'app_open_sessions_count {open_sessions_count}')

    return '\n'.join(prom_metrics)

@app.route('/health')
def health():
    """Health check endpoint for liveness/readiness probes"""
    try:
        # Simple health check - just verify we can respond
        if shutdown_event.is_set():
            return Response("Shutting down", status=503, mimetype='text/plain')
        
        # Check if we've had too many consecutive failures
        if healthcheck_failures['fetch'] > 10:
            return Response("Too many fetch failures", status=503, mimetype='text/plain')
            
        return Response("OK", status=200, mimetype='text/plain')
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return Response("Health check failed", status=503, mimetype='text/plain')

@app.route('/metrics')
def metrics():
    try:
        metrics_data = fetch_metrics()
        prom_metrics = convert_to_prometheus(metrics_data)
        return Response(prom_metrics, mimetype='text/plain')
    except Exception as e:
        logger.error(f"Error fetching metrics: {e}")
        
        # Return minimal metrics to keep HPA functioning
        minimal_metrics = [
            '# HELP app_active_task_count The number of active tasks.',
            '# TYPE app_active_task_count gauge',
            'app_active_task_count 0',
            '# HELP app_active_request_count The number of active requests.',
            '# TYPE app_active_request_count gauge', 
            'app_active_request_count 0',
            '# HELP app_agent_status Shows if the agent is running. (1 for running, 0 for not)',
            '# TYPE app_agent_status gauge',
            'app_agent_status 0'
        ]
        
        return Response('\n'.join(minimal_metrics), status=200, mimetype='text/plain')

def create_app():
    """Application factory for production deployment"""
    return app

if __name__ == '__main__':
    try:
        logger.info(f"Starting metrics exporter on port 8000")
        logger.info(f"Metrics endpoint: {METRICS_ENDPOINT}")
        logger.info(f"Grace period: {GRACE_PERIOD_SECONDS} seconds")
        
        # Use Gunicorn in production, Flask dev server for development
        import os
        if os.environ.get('PRODUCTION', '').lower() == 'true':
            # Production: Use gunicorn via command line
            logger.info("Production mode detected - use 'gunicorn -w 2 -b 0.0.0.0:8000 custom_metics_exporter:app'")
            sys.exit(0)
        else:
            # Development: Use Flask dev server
            logger.info("Development mode - using Flask dev server")
            app.run(host='0.0.0.0', port=8000, threaded=True)
    except Exception as e:
        logger.error(f"Failed to start metrics exporter: {e}")
        sys.exit(1)