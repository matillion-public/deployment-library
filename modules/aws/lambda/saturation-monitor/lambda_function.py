"""
AWS Lambda Function: ECS Runner Saturation Monitor

Discovers ECS services running Matillion runners, fetches saturation metrics from their
actuator endpoints, and publishes them to CloudWatch for cluster monitoring.
"""

import json
import logging
import os
import boto3
import urllib.request
import urllib.error
from datetime import datetime
from typing import Dict, List, Any, Optional
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

class ECSRunnerSaturationMonitor:
    def __init__(self):
        self.ecs = boto3.client('ecs')
        self.ec2 = boto3.client('ec2')
        self.cloudwatch = boto3.client('cloudwatch')
        self.cloudwatch_namespace = 'ECS/RunnerSaturation'

    def discover_runner_services(self) -> List[Dict[str, Any]]:
        """Discover ECS services running Matillion runners"""
        runner_services = []

        try:
            # List all ECS clusters
            clusters_response = self.ecs.list_clusters()
            cluster_arns = clusters_response['clusterArns']

            for cluster_arn in cluster_arns:
                cluster_name = cluster_arn.split('/')[-1]

                # List services in each cluster
                services_response = self.ecs.list_services(cluster=cluster_arn)
                service_arns = services_response['serviceArns']

                if not service_arns:
                    continue

                # Describe services to get details
                services_detail = self.ecs.describe_services(
                    cluster=cluster_arn,
                    services=service_arns
                )

                for service in services_detail['services']:
                    service_name = service['serviceName']

                    # Check if this looks like a Matillion runner service
                    if self._is_runner_service(service_name, service):
                        # Get running tasks for this service
                        tasks = self._get_service_tasks(cluster_arn, service['serviceArn'])

                        for task in tasks:
                            task_ips = self._get_task_ips(task)
                            agent_id = self._extract_agent_id(task)

                            runner_info = {
                                'cluster_name': cluster_name,
                                'cluster_arn': cluster_arn,
                                'service_name': service_name,
                                'service_arn': service['serviceArn'],
                                'task_arn': task['taskArn'],
                                'task_definition_arn': task['taskDefinitionArn'],
                                'private_ip': task_ips['private'],
                                'public_ip': task_ips['public'],
                                'agent_id': agent_id
                            }

                            ip_info = f"Private: {task_ips['private']}"
                            if task_ips['public']:
                                ip_info += f", Public: {task_ips['public']}"

                            logger.info(f"Discovered runner: {service_name} in {cluster_name}, {ip_info}, Agent ID: {agent_id}")
                            runner_services.append(runner_info)

            logger.info(f"Discovered {len(runner_services)} runner tasks across {len(cluster_arns)} clusters")
            return runner_services

        except Exception as e:
            logger.error(f"Error discovering runner services: {e}")
            return []

    def _is_runner_service(self, service_name: str, service: Dict) -> bool:
        """Determine if a service is a Matillion runner service"""
        # Get runner indicators from environment variable, fallback to defaults.
        # Includes "agent" alongside "runner" for backward-compat discovery of older deployments.
        indicators_env = os.environ.get('RUNNER_SERVICE_INDICATORS', 'matillion,runner,agent,dpc')
        indicators = [indicator.strip().lower() for indicator in indicators_env.split(',')]

        service_name_lower = service_name.lower()
        return any(indicator in service_name_lower for indicator in indicators)

    def _get_service_tasks(self, cluster_arn: str, service_arn: str) -> List[Dict]:
        """Get running tasks for a service"""
        try:
            tasks_response = self.ecs.list_tasks(
                cluster=cluster_arn,
                serviceName=service_arn,
                desiredStatus='RUNNING'
            )

            if not tasks_response['taskArns']:
                return []

            # Get detailed task information
            tasks_detail = self.ecs.describe_tasks(
                cluster=cluster_arn,
                tasks=tasks_response['taskArns']
            )

            return tasks_detail['tasks']

        except Exception as e:
            logger.error(f"Error getting tasks for service {service_arn}: {e}")
            return []

    def _get_task_ips(self, task: Dict) -> Dict[str, Optional[str]]:
        """Extract both private and public IP addresses from task"""
        ips = {'private': None, 'public': None}

        try:
            for attachment in task.get('attachments', []):
                if attachment['type'] == 'ElasticNetworkInterface':
                    for detail in attachment['details']:
                        if detail['name'] == 'privateIPv4Address':
                            ips['private'] = detail['value']
                        elif detail['name'] == 'publicIPv4Address':
                            ips['public'] = detail['value']
        except Exception as e:
            logger.debug(f"Could not extract IPs from task: {e}")

        return ips

    def _extract_agent_id(self, task: Dict) -> str:
        """Extract Matillion Agent ID from task environment variables (API contract field name) or use task ID"""
        try:
            # Try to get from task definition environment variables
            task_def_arn = task['taskDefinitionArn']
            task_def = self.ecs.describe_task_definition(taskDefinition=task_def_arn)

            for container in task_def['taskDefinition']['containerDefinitions']:
                for env_var in container.get('environment', []):
                    if env_var['name'] == 'AGENT_ID':
                        return env_var['value']
        except Exception as e:
            logger.debug(f"Could not extract Agent ID from environment: {e}")

        # Fallback to task ID
        return task['taskArn'].split('/')[-1]

    def fetch_runner_metrics(self, runner_info: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Fetch metrics from runner actuator endpoint with smart IP selection"""
        private_ip = runner_info.get('private_ip')
        public_ip = runner_info.get('public_ip')

        if not private_ip and not public_ip:
            logger.warning(f"No IP addresses available for task {runner_info['task_arn']}")
            return None

        # Build list of IPs to try based on deployment mode
        deployment_mode = os.environ.get('DEPLOYMENT_MODE', 'hybrid')
        ips_to_try = []

        if deployment_mode == 'public':
            # Only try public IP
            if public_ip:
                ips_to_try.append(('public', public_ip))
        elif deployment_mode == 'private':
            # Only try private IP
            if private_ip:
                ips_to_try.append(('private', private_ip))
        else:
            # Hybrid mode: prefer public IP for Lambda outside VPC, but try both
            if public_ip:
                ips_to_try.append(('public', public_ip))
            if private_ip:
                ips_to_try.append(('private', private_ip))

        # Try different ports and endpoints for each IP
        endpoint_patterns = [
            ('actuator/info', 8080),
            ('metrics', 8000),
            ('actuator/metrics', 8080),
            ('actuator/health', 8080),
        ]

        for ip_type, ip_address in ips_to_try:
            logger.debug(f"Trying {ip_type} IP: {ip_address}")

            for endpoint_path, port in endpoint_patterns:
                endpoint = f"http://{ip_address}:{port}/{endpoint_path}"

                try:
                    logger.debug(f"Trying endpoint: {endpoint}")
                    req = urllib.request.Request(endpoint)
                    with urllib.request.urlopen(req, timeout=5) as response:  # Reduced timeout for faster fallback
                        if response.getcode() == 200:
                            data = response.read().decode('utf-8')
                            metrics_data = json.loads(data)
                            logger.info(f"Fetched metrics from {endpoint} ({ip_type} IP): {metrics_data}")
                            logger.info(f"Successfully fetched metrics from {endpoint} ({ip_type} IP)")
                            return metrics_data
                        else:
                            logger.debug(f"HTTP {response.getcode()} from {endpoint}")
                            continue

                except (urllib.error.URLError, urllib.error.HTTPError, json.JSONDecodeError, Exception) as e:
                    logger.debug(f"Failed to fetch from {endpoint}: {e}")
                    continue

        ip_summary = []
        if public_ip:
            ip_summary.append(f"public:{public_ip}")
        if private_ip:
            ip_summary.append(f"private:{private_ip}")

        logger.warning(f"Could not fetch metrics from any endpoint for task {runner_info['task_arn']} (tried IPs: {', '.join(ip_summary)})")
        return None

    def publish_metrics_to_cloudwatch(self, runner_info: Dict[str, Any], metrics_data: Dict[str, Any]):
        """Publish saturation metrics to CloudWatch"""
        try:
            # Use task ID for unique identification of each running instance
            task_id = runner_info['task_arn'].split('/')[-1]

            dimensions = [
                {'Name': 'ClusterName', 'Value': runner_info['cluster_name']},
                {'Name': 'ServiceName', 'Value': runner_info['service_name']},
                {'Name': 'TaskId', 'Value': task_id},
                {'Name': 'RunnerId', 'Value': runner_info['agent_id']}
            ]

            metric_data = []
            timestamp = datetime.utcnow()

            # Active Task Count - primary saturation indicator
            if 'activeTaskCount' in metrics_data:
                metric_data.append({
                    'MetricName': 'ActiveTaskCount',
                    'Value': float(metrics_data['activeTaskCount']),
                    'Unit': 'Count',
                    'Dimensions': dimensions,
                    'Timestamp': timestamp
                })

            # Active Request Count - queue saturation indicator
            if 'activeRequestCount' in metrics_data:
                metric_data.append({
                    'MetricName': 'ActiveRequestCount',
                    'Value': float(metrics_data['activeRequestCount']),
                    'Unit': 'Count',
                    'Dimensions': dimensions,
                    'Timestamp': timestamp
                })

            # Open Sessions Count - connection saturation indicator
            if 'openSessionsCount' in metrics_data:
                metric_data.append({
                    'MetricName': 'OpenSessionsCount',
                    'Value': float(metrics_data['openSessionsCount']),
                    'Unit': 'Count',
                    'Dimensions': dimensions,
                    'Timestamp': timestamp
                })

            # Runner Status - health indicator. The actuator returns `agentStatus` (Matillion API contract).
            agent_status = metrics_data.get('agentStatus', '')
            runner_status_value = 1.0 if agent_status == 'RUNNING' else 0.0
            metric_data.append({
                'MetricName': 'RunnerStatus',
                'Value': runner_status_value,
                'Unit': 'None',
                'Dimensions': dimensions,
                'Timestamp': timestamp
            })

            if not metric_data:
                logger.warning(f"No metrics to publish for task {task_id} (agent_id {runner_info['agent_id']})")
                return

            # Log the metrics being published
            logger.info(f"Publishing metrics for task {task_id} (agent_id {runner_info['agent_id']}): {json.dumps(metric_data, indent=2, default=str)}")

            # Publish to CloudWatch
            self.cloudwatch.put_metric_data(
                Namespace=self.cloudwatch_namespace,
                MetricData=metric_data
            )

            logger.info(f"Published {len(metric_data)} metrics for task {task_id} (agent_id {runner_info['agent_id']}) "
                       f"in cluster {runner_info['cluster_name']}")

        except Exception as e:
            logger.error(f"Error publishing metrics for task {task_id} (agent_id {runner_info['agent_id']}): {e}")

    def monitor_all_runners(self) -> Dict[str, Any]:
        """Main monitoring function - discover and monitor all runners"""
        results = {
            'runners_discovered': 0,
            'runners_monitored': 0,
            'metrics_published': 0,
            'errors': []
        }

        try:
            # Discover all runner services
            runner_services = self.discover_runner_services()
            results['runners_discovered'] = len(runner_services)

            if not runner_services:
                logger.info("No runner services discovered")
                return results

            # Monitor each runner
            for runner_info in runner_services:
                try:
                    # Fetch metrics from runner
                    metrics_data = self.fetch_runner_metrics(runner_info)

                    if metrics_data:
                        # Publish to CloudWatch
                        self.publish_metrics_to_cloudwatch(runner_info, metrics_data)
                        results['runners_monitored'] += 1
                        results['metrics_published'] += 4  # Assuming 4 metrics per runner

                except Exception as e:
                    error_msg = f"Error monitoring runner {runner_info.get('agent_id', 'unknown')}: {e}"
                    logger.error(error_msg)
                    results['errors'].append(error_msg)

            logger.info(f"Monitoring complete: {results['runners_monitored']}/{results['runners_discovered']} "
                       f"runners monitored, {results['metrics_published']} metrics published")

        except Exception as e:
            error_msg = f"Fatal error in monitoring: {e}"
            logger.error(error_msg)
            results['errors'].append(error_msg)

        return results

def lambda_handler(event, context):
    """Lambda entry point"""
    logger.info("Starting ECS Runner Saturation Monitor")

    try:
        monitor = ECSRunnerSaturationMonitor()
        results = monitor.monitor_all_runners()

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Runner monitoring completed successfully',
                'results': results
            })
        }

    except Exception as e:
        logger.error(f"Lambda execution failed: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Runner monitoring failed',
                'error': str(e)
            })
        }
