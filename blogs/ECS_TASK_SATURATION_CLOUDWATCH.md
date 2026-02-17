# ECS Task Saturation Monitoring with CloudWatch Lambda

## Overview

This document outlines how to surface task saturation metrics from the agent actuator endpoint to CloudWatch for monitoring ECS cluster utilization and saturation levels using a serverless Lambda approach.

## Current Task Saturation Metrics

The agent actuator endpoint provides these key saturation indicators:

- **`activeTaskCount`** - Number of active tasks being processed (indicates processing load)
- **`activeRequestCount`** - Number of active requests queued/processing (indicates queue saturation) 
- **`openSessionsCount`** - Number of open sessions (indicates connection saturation)
- **`agentStatus`** - Agent health status (RUNNING/STOPPED)

These metrics provide visibility into how busy/saturated each ECS task (agent) is.

## Lambda-Based Implementation Approach

Instead of running a sidecar container in ECS, we use a Lambda function that:

1. **Discovers ECS Services** - Automatically finds Matillion agent services across all clusters
2. **Fetches Metrics** - Calls actuator endpoints on each agent task
3. **Publishes to CloudWatch** - Sends saturation metrics with proper dimensions
4. **Runs on Schedule** - EventBridge triggers every minute

### Architecture

```
┌─────────────────┐    ┌──────────────────────┐    ┌─────────────────┐
│   EventBridge   │───▶│   Lambda Function    │───▶│   CloudWatch    │
│   (1min rule)   │    │   - Discover ECS     │    │   Metrics       │
└─────────────────┘    │   - Fetch Metrics    │    └─────────────────┘
                       │   - Publish Metrics  │
                       └──────────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │   ECS Clusters  │
                       │   (Agent Tasks) │
                       └─────────────────┘
```

## Lambda Function Implementation

The Lambda function is located at `modules/aws/lambda/saturation-monitor/lambda_function.py` and includes:

- **Service Discovery**: Automatically discovers ECS services running Matillion agents
- **Metric Fetching**: Connects to agent actuator endpoints via private IP
- **CloudWatch Publishing**: Publishes metrics with proper dimensions
- **Error Handling**: Resilient to individual agent failures

### Key Features

1. **Auto-Discovery**: Finds agent services by name patterns (`matillion`, `agent`, `dpc`)
2. **Private Network Access**: Uses ECS task private IPs to call actuator endpoints
3. **Dimensional Metrics**: Includes ClusterName, ServiceName, and AgentId dimensions
4. **Batch Publishing**: Efficiently publishes multiple metrics per API call

## CloudWatch Metrics Structure

### Namespace
`ECS/AgentSaturation`

### Metrics
| Metric Name | Unit | Description |
|------------|------|-------------|
| `ActiveTaskCount` | Count | Number of tasks actively being processed by the agent |
| `ActiveRequestCount` | Count | Number of requests queued or being processed |
| `OpenSessionsCount` | Count | Number of open sessions/connections |

### Dimensions
- `ClusterName` - ECS cluster name
- `ServiceName` - ECS service name

## Monitoring ECS Cluster Saturation

### CloudWatch Dashboard

Create a dashboard to visualize cluster-wide saturation:

```json
{
    "widgets": [
        {
            "type": "metric",
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["ECS/AgentSaturation", "ActiveTaskCount", "ClusterName", "your-cluster-name"],
                    [".", "ActiveRequestCount", ".", "."],
                    [".", "OpenSessionsCount", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "us-east-1", 
                "title": "ECS Cluster Saturation - Total Load",
                "view": "timeSeries",
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
            }
        },
        {
            "type": "metric",
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["ECS/AgentSaturation", "ActiveTaskCount", "ClusterName", "your-cluster-name"],
                    [".", "ActiveRequestCount", ".", "."],
                    [".", "OpenSessionsCount", ".", "."]
                ],
                "period": 300,
                "stat": "Average",
                "region": "us-east-1", 
                "title": "ECS Cluster Saturation - Average per Task",
                "view": "timeSeries"
            }
        }
    ]
}
```

### CloudWatch Alarms for Saturation

Set up alarms to detect high saturation:

```bash
# High average task count per ECS task
aws cloudwatch put-metric-alarm \
    --alarm-name "ECS-AgentSaturation-HighTaskCount" \
    --alarm-description "Alert when average active task count is high" \
    --metric-name ActiveTaskCount \
    --namespace ECS/AgentSaturation \
    --statistic Average \
    --period 300 \
    --threshold 50 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2

# High request queue buildup
aws cloudwatch put-metric-alarm \
    --alarm-name "ECS-AgentSaturation-HighRequestQueue" \
    --alarm-description "Alert when request queue is building up" \
    --metric-name ActiveRequestCount \
    --namespace ECS/AgentSaturation \
    --statistic Average \
    --period 300 \
    --threshold 20 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2

# High session count indicating connection pressure
aws cloudwatch put-metric-alarm \
    --alarm-name "ECS-AgentSaturation-HighSessions" \
    --alarm-description "Alert when session count is high" \
    --metric-name OpenSessionsCount \
    --namespace ECS/AgentSaturation \
    --statistic Average \
    --period 300 \
    --threshold 100 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2
```

## ECS Auto Scaling Based on Saturation

Use saturation metrics for ECS service auto scaling:

```hcl
# Auto scaling target
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 10
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.matillion_dpc_cluster.name}/${aws_ecs_service.matillion_dpc_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Scale up based on active task count
resource "aws_appautoscaling_policy" "scale_up_on_tasks" {
  name               = "${var.name}-scale-up-on-tasks"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    customized_metric_specification {
      metric_name = "ActiveTaskCount"
      namespace   = "ECS/AgentSaturation"
      statistic   = "Average"
      
      dimensions = {
        ClusterName = aws_ecs_cluster.matillion_dpc_cluster.name
        ServiceName = aws_ecs_service.matillion_dpc_service.name
      }
    }
    target_value = 30.0  # Target 30 active tasks per ECS task on average
  }
}
```

## Terraform Deployment

### 1. Add Lambda Module to Your Configuration

Add the Lambda module to your main Terraform configuration:

```hcl
# In your main.tf or wherever you call the ECS module
module "saturation_monitor" {
  source = "./modules/aws/lambda/saturation-monitor"
  
  name                           = var.name
  cloudwatch_namespace          = "ECS/AgentSaturation"
  schedule_expression           = "rate(1 minute)"
  log_level                     = "INFO"
  create_dashboard              = true
  create_alarms                 = true
  high_task_count_threshold     = 50
  high_request_count_threshold  = 20
  alarm_actions                 = [] 
  agent_service_indicators      = "matillion,agent,dpc,my-custom-service" 
}
```

### 2. Deploy the Lambda Function

```bash
# Navigate to your terraform directory
cd /path/to/your/terraform

# Plan the deployment
terraform plan

# Apply the changes
terraform apply
```

### 3. Verification Steps

After deployment, verify the setup:

```bash
# Check Lambda function was created
aws lambda get-function --function-name ${name}-saturation-monitor

# Check EventBridge rule
aws events describe-rule --name ${name}-saturation-monitor-schedule

# Manually invoke Lambda to test
aws lambda invoke --function-name ${name}-saturation-monitor --payload '{}' response.json

# Check CloudWatch metrics
aws cloudwatch list-metrics --namespace "ECS/AgentSaturation"
```

## IAM Permissions

The existing ECS task role already includes the necessary CloudWatch permissions:
- `cloudwatch:PutMetricData` (line 55 in `modules/aws/iam/templates/ecs_task_role_policy.json`)