# Gunicorn configuration for metrics exporter
import os
import multiprocessing

# Server socket
bind = "0.0.0.0:8000"

# Worker processes
workers = 2  # Keep low for sidecar container
worker_class = "sync"
worker_connections = 100
max_requests = 1000
max_requests_jitter = 100

# Timeout settings
timeout = 30
keepalive = 5
graceful_timeout = 30

# Preload application for better performance
preload_app = True

# Logging
loglevel = "info"
accesslog = "-"
errorlog = "-"
access_log_format = '%(h)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s" %(D)s'

# Process naming
proc_name = "metrics-exporter"

# Security
limit_request_line = 4096
limit_request_fields = 100
limit_request_field_size = 8190

# Signal handling for graceful shutdown
def on_starting(server):
    server.log.info("Starting metrics exporter with Gunicorn")

def on_exit(server):
    server.log.info("Shutting down metrics exporter")