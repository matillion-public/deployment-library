"""
AWS Lambda Function: ECS Agent Saturation Monitor

Discovers ECS services running Matillion agents, fetches saturation metrics from their
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

class ECSAgentSaturationMonitor:
    def __init__(self):
        self.ecs = boto3.client('ecs')
        self.ec2 = boto3.client('ec2')
        self.cloudwatch = boto3.client('cloudwatch')
        self.cloudwatch_namespace = 'ECS/AgentSaturation'
        
    def discover_agent_services(self) -> List[Dict[str, Any]]:
        """Discover ECS services running Matillion agents"""
        agent_services = []
        
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
                    
                    # Check if this looks like a Matillion agent service
                    if self._is_agent_service(service_name, service):
                        # Get running tasks for this service
                        tasks = self._get_service_tasks(cluster_arn, service['serviceArn'])
                        
                        for task in tasks:
                            task_ips = self._get_task_ips(task)
                            agent_id = self._extract_agent_id(task)
                            
                            agent_info = {
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
                            
                            logger.info(f"Discovered agent: {service_name} in {cluster_name}, {ip_info}, Agent ID: {agent_id}")
                            agent_services.append(agent_info)
            
            logger.info(f"Discovered {len(agent_services)} agent tasks across {len(cluster_arns)} clusters")
            return agent_services
            
        except Exception as e:
            logger.error(f"Error discovering agent services: {e}")
            return []
    
    def _is_agent_service(self, service_name: str, service: Dict) -> bool:
        """Determine if a service is a Matillion agent service"""
        # Get agent indicators from environment variable, fallback to defaults
        agent_indicators_env = os.environ.get('AGENT_SERVICE_INDICATORS', 'matillion,agent,dpc')
        agent_indicators = [indicator.strip().lower() for indicator in agent_indicators_env.split(',')]
        
        service_name_lower = service_name.lower()
        return any(indicator in service_name_lower for indicator in agent_indicators)
    
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
        """Extract agent ID from task environment variables or use task ID"""
        try:
            # Try to get from task definition environment variables
            task_def_arn = task['taskDefinitionArn']
            task_def = self.ecs.describe_task_definition(taskDefinition=task_def_arn)
            
            for container in task_def['taskDefinition']['containerDefinitions']:
                for env_var in container.get('environment', []):
                    if env_var['name'] == 'AGENT_ID':
                        return env_var['value']
        except Exception as e:
            logger.debug(f"Could not extract agent ID from environment: {e}")
        
        # Fallback to task ID
        return task['taskArn'].split('/')[-1]
    
    def fetch_agent_metrics(self, agent_info: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Fetch metrics from agent actuator endpoint with smart IP selection"""
        private_ip = agent_info.get('private_ip')
        public_ip = agent_info.get('public_ip')
        
        if not private_ip and not public_ip:
            logger.warning(f"No IP addresses available for task {agent_info['task_arn']}")
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
        
        logger.warning(f"Could not fetch metrics from any endpoint for task {agent_info['task_arn']} (tried IPs: {', '.join(ip_summary)})")
        return None
    
    def publish_metrics_to_cloudwatch(self, agent_info: Dict[str, Any], metrics_data: Dict[str, Any]):
        """Publish saturation metrics to CloudWatch"""
        try:
            # Use task ID for unique identification of each running instance
            task_id = agent_info['task_arn'].split('/')[-1]
            
            dimensions = [
                {'Name': 'ClusterName', 'Value': agent_info['cluster_name']},
                {'Name': 'ServiceName', 'Value': agent_info['service_name']},
                {'Name': 'TaskId', 'Value': task_id},
                {'Name': 'AgentId', 'Value': agent_info['agent_id']}
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
            
            # Agent Status - health indicator
            agent_status = metrics_data.get('agentStatus', '')
            agent_status_value = 1.0 if agent_status == 'RUNNING' else 0.0
            metric_data.append({
                'MetricName': 'AgentStatus',
                'Value': agent_status_value,
                'Unit': 'None',
                'Dimensions': dimensions,
                'Timestamp': timestamp
            })
            
            if not metric_data:
                logger.warning(f"No metrics to publish for task {task_id} (agent {agent_info['agent_id']})")
                return
            
            # Log the metrics being published
            logger.info(f"Publishing metrics for task {task_id} (agent {agent_info['agent_id']}): {json.dumps(metric_data, indent=2, default=str)}")
            
            # Publish to CloudWatch
            self.cloudwatch.put_metric_data(
                Namespace=self.cloudwatch_namespace,
                MetricData=metric_data
            )
            
            logger.info(f"Published {len(metric_data)} metrics for task {task_id} (agent {agent_info['agent_id']}) "
                       f"in cluster {agent_info['cluster_name']}")
            
        except Exception as e:
            logger.error(f"Error publishing metrics for task {task_id} (agent {agent_info['agent_id']}): {e}")
    
    def monitor_all_agents(self) -> Dict[str, Any]:
        """Main monitoring function - discover and monitor all agents"""
        results = {
            'agents_discovered': 0,
            'agents_monitored': 0,
            'metrics_published': 0,
            'errors': []
        }
        
        try:
            # Discover all agent services
            agent_services = self.discover_agent_services()
            results['agents_discovered'] = len(agent_services)
            
            if not agent_services:
                logger.info("No agent services discovered")
                return results
            
            # Monitor each agent
            for agent_info in agent_services:
                try:
                    # Fetch metrics from agent
                    metrics_data = self.fetch_agent_metrics(agent_info)
                    
                    if metrics_data:
                        # Publish to CloudWatch
                        self.publish_metrics_to_cloudwatch(agent_info, metrics_data)
                        results['agents_monitored'] += 1
                        results['metrics_published'] += 4  # Assuming 4 metrics per agent
                    
                except Exception as e:
                    error_msg = f"Error monitoring agent {agent_info.get('agent_id', 'unknown')}: {e}"
                    logger.error(error_msg)
                    results['errors'].append(error_msg)
            
            logger.info(f"Monitoring complete: {results['agents_monitored']}/{results['agents_discovered']} "
                       f"agents monitored, {results['metrics_published']} metrics published")
            
        except Exception as e:
            error_msg = f"Fatal error in monitoring: {e}"
            logger.error(error_msg)
            results['errors'].append(error_msg)
        
        return results

def lambda_handler(event, context):
    """Lambda entry point"""
    logger.info("Starting ECS Agent Saturation Monitor")
    
    try:
        monitor = ECSAgentSaturationMonitor()
        results = monitor.monitor_all_agents()
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Agent monitoring completed successfully',
                'results': results
            })
        }
        
    except Exception as e:
        logger.error(f"Lambda execution failed: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Agent monitoring failed',
                'error': str(e)
            })
        }