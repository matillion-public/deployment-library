# Autoscaling Matillion Agents: Smart Scaling for Data Workloads

Modern data processing workloads are inherently unpredictable. Data volumes fluctuate throughout the day, pipeline complexity varies, and business demands change rapidly. Traditional static resource allocation leads to either over-provisioning (wasting money) or under-provisioning (degrading performance). The Matillion Agent Deployment repository solves this with sophisticated autoscaling capabilities that respond intelligently to actual workload demands.

## Why Traditional Metrics Fall Short for Data Agents

Most autoscaling solutions rely on basic CPU and memory metrics. For data processing agents, this approach is problematic:

- **CPU spikes** don't always indicate high workload (could be garbage collection)
- **Memory usage** varies significantly based on data set sizes, not necessarily workload
- **Network I/O** can be high during data transfers but low during processing
- **Traditional metrics** don't reflect the actual business value: **active data tasks**

## Smart Autoscaling with Custom Metrics

This repository implements **application-aware autoscaling** using custom metrics that actually matter for data processing:

### Key Metrics for Intelligent Scaling

1. **`app_active_task_count`** - Number of data processing tasks currently executing
2. **`app_active_request_count`** - Number of active API requests being handled
3. **Task completion rate** - Historical data for predictive scaling

These metrics provide a true picture of agent workload and enable more accurate scaling decisions.

## Kubernetes Autoscaling: The Gold Standard

### Horizontal Pod Autoscaler (HPA) with Custom Metrics

The Kubernetes deployment includes a sophisticated HPA configuration that scales based on real workload metrics:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: matillion-agent-hpa
spec:
  behavior:
    scaleDown:
      policies:
      - periodSeconds: 60
        type: Pods
        value: 1
      selectPolicy: Min
      stabilizationWindowSeconds: 300  # 5-minute stabilization
    scaleUp:
      policies:
      - periodSeconds: 30
        type: Pods
        value: 2
      selectPolicy: Max
      stabilizationWindowSeconds: 60   # 1-minute stabilization
  maxReplicas: 10
  minReplicas: 2
  metrics:
  - pods:
      metric:
        name: app_active_task_count
      target:
        averageValue: "70"
        type: AverageValue
  - pods:
      metric:
        name: app_active_request_count
      target:
        averageValue: "50"
        type: AverageValue
```

### Scaling Behavior Policies

The configuration includes intelligent scaling behaviors:

#### Scale-Up Policies
- **Fast Response**: 2 pods every 30 seconds when demand increases
- **Short Stabilization**: 60-second window to prevent flapping
- **Aggressive Growth**: Handles sudden workload spikes efficiently

#### Scale-Down Policies
- **Conservative Approach**: 1 pod every 60 seconds when demand decreases
- **Long Stabilization**: 5-minute window to prevent premature scaling down
- **Cost Optimization**: Gradual reduction to avoid resource waste

### Production vs Development Scaling Profiles

#### Production Configuration
```yaml
hpa:
  minReplicas: 2              # High availability baseline
  maxReplicas: 10             # Generous headroom for peak loads
  metrics:
    target:
      averageValue: "70"      # Conservative threshold
  scaleDown:
    stabilizationWindowSeconds: 300  # Stable, predictable scaling
  scaleUp:
    stabilizationWindowSeconds: 60   # Responsive to business needs
```

#### Development/Testing Configuration
```yaml
hpa:
  minReplicas: 1              # Cost-effective baseline
  maxReplicas: 5              # Limited resource usage
  metrics:
    target:
      averageValue: "10"      # Aggressive scaling for testing
  scaleDown:
    stabilizationWindowSeconds: 180  # Faster scale-down for cost savings
  scaleUp:
    stabilizationWindowSeconds: 0    # Immediate response for testing
```

## Prometheus Custom Metrics Infrastructure

### Complete Metrics Pipeline

The repository includes a full metrics infrastructure:

```yaml
# Prometheus Adapter Configuration
adapterConfig:
  configYaml: |-
    rules:
      - seriesQuery: 'app_active_task_count{container!="POD",namespace!="",pod!=""}'
        resources:
          overrides:
            namespace: {resource: "namespace"}
            pod: {resource: "pod"}
        name:
          matches: "app_.*"
          as: "app_active_task_count"
        metricsQuery: 'avg_over_time(<<.Series>>{<<.LabelMatchers>>}[1m])'
```

### Metrics Collection Flow

1. **Agent Sidecar** exposes metrics on port 8000
2. **Prometheus** scrapes metrics every 15 seconds
3. **Prometheus Adapter** converts metrics to Kubernetes custom metrics API
4. **HPA Controller** queries custom metrics for scaling decisions
5. **Kubernetes Scheduler** provisions new pods as needed

## AWS ECS Autoscaling Strategy

While the current ECS implementation focuses on simplicity, it can be extended with Application Auto Scaling:

### ECS Auto Scaling Configuration

```hcl
# Scalable Target
resource "aws_appautoscaling_target" "matillion_agent" {
  max_capacity       = 10
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# CPU-based Scaling Policy
resource "aws_appautoscaling_policy" "cpu_scaling" {
  name               = "matillion-agent-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.matillion_agent.resource_id
  scalable_dimension = aws_appautoscaling_target.matillion_agent.scalable_dimension
  service_namespace  = aws_appautoscaling_target.matillion_agent.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300  # 5 minutes
    scale_out_cooldown = 60   # 1 minute
  }
}

# Memory-based Scaling Policy
resource "aws_appautoscaling_policy" "memory_scaling" {
  name               = "matillion-agent-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.matillion_agent.resource_id
  scalable_dimension = aws_appautoscaling_target.matillion_agent.scalable_dimension
  service_namespace  = aws_appautoscaling_target.matillion_agent.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = 80.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
```

### ECS Scaling Advantages
- **Serverless Scaling**: Fargate handles infrastructure automatically
- **Cost Efficiency**: Pay only for running tasks
- **AWS Integration**: Native CloudWatch metrics and alarms
- **Granular Control**: Per-service scaling policies

## Azure AKS: Multi-Level Scaling

Azure AKS provides scaling at multiple levels:

### Cluster Auto Scaling
```hcl
default_node_pool {
  name                 = "agentpool"
  vm_size              = "Standard_D4s_v4"
  auto_scaling_enabled = true
  min_count            = 2
  max_count            = 20
  node_count           = 3
  vnet_subnet_id       = var.subnet_id
}
```

### Benefits of AKS Auto Scaling
- **Node-level Scaling**: Automatically provisions VMs based on pod resource requests
- **Cost Optimization**: Scales down unused nodes during low-demand periods
- **Resource Efficiency**: Right-sizes cluster capacity to actual needs
- **Azure Integration**: Works with Azure Monitor and Log Analytics

## Advanced Autoscaling Patterns

### Predictive Scaling
While not implemented in the current version, the infrastructure supports predictive scaling:

```yaml
# Future enhancement: Predictive scaling based on historical patterns
apiVersion: v1
kind: ConfigMap
metadata:
  name: scaling-predictions
data:
  monday_morning_scale_up: "8:00"    # Pre-scale for business hours
  friday_evening_scale_down: "18:00" # Cost optimization for weekends
  month_end_surge: "28-31"          # Handle month-end reporting loads
```

### Multi-Metric Scaling
Combine different metrics for more intelligent scaling decisions:

```yaml
metrics:
- pods:
    metric:
      name: app_active_task_count
    target:
      averageValue: "70"
- pods:
    metric:
      name: app_queue_depth
    target:
      averageValue: "100"
- resource:
    name: memory
    target:
      type: Utilization
      averageUtilization: 80
```

### Event-Driven Scaling
Integration with external events:

```yaml
# KEDA ScaledObject for event-driven scaling
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: matillion-agent-scaler
spec:
  scaleTargetRef:
    name: matillion-agent
  triggers:
  - type: prometheus
    metadata:
      serverAddress: http://prometheus:9090
      metricName: app_pending_tasks
      threshold: '50'
      query: sum(app_pending_tasks)
```

## Scaling Best Practices

### Right-Sizing Your Scaling Configuration

#### For High-Volume, Predictable Workloads
```yaml
hpa:
  minReplicas: 5              # Higher baseline for consistent load
  maxReplicas: 15             # Generous headroom
  metrics:
    target:
      averageValue: "80"      # Higher threshold (fewer scale events)
  scaleDown:
    stabilizationWindowSeconds: 600  # 10-minute stabilization
```

#### For Sporadic, Bursty Workloads
```yaml
hpa:
  minReplicas: 1              # Cost-effective baseline
  maxReplicas: 20             # Handle sudden spikes
  metrics:
    target:
      averageValue: "30"      # Lower threshold (more responsive)
  scaleUp:
    stabilizationWindowSeconds: 30   # Fast response to bursts
```

#### For Development/Testing
```yaml
hpa:
  minReplicas: 1
  maxReplicas: 3
  metrics:
    target:
      averageValue: "10"      # Scale early for testing
```

### Monitoring and Alerting

Set up comprehensive monitoring for your scaling events:

```yaml
# Prometheus Alert Rules
groups:
- name: matillion-agent-scaling
  rules:
  - alert: AgentScalingTooFrequent
    expr: increase(kube_hpa_status_desired_replicas[5m]) > 3
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "Agent scaling happening too frequently"
      
  - alert: AgentMaxReplicasReached
    expr: kube_hpa_status_current_replicas == kube_hpa_spec_max_replicas
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "Agent has reached maximum replicas - may need capacity planning"
```

### Cost Optimization Strategies

1. **Vertical Pod Autoscaling (VPA)**: Right-size resource requests
2. **Node Affinity**: Place pods on cost-effective node types
3. **Spot Instances**: Use preemptible instances for non-critical workloads
4. **Schedule-based Scaling**: Pre-scale during known high-demand periods

## Troubleshooting Autoscaling Issues

### Common Problems and Solutions

#### Scaling Events Not Triggering
**Symptoms**: HPA shows correct metrics but doesn't scale
**Causes**:
- Metrics server not running
- Custom metrics API not available
- Insufficient RBAC permissions

**Solutions**:
```bash
# Check metrics server
kubectl top pods

# Verify custom metrics
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1"

# Check HPA status
kubectl describe hpa matillion-agent-hpa
```

#### Rapid Scaling Oscillations
**Symptoms**: Pods scaling up and down repeatedly
**Causes**:
- Metrics fluctuating around threshold
- Short stabilization windows
- Resource contention

**Solutions**:
```yaml
# Increase stabilization windows
scaleDown:
  stabilizationWindowSeconds: 300
scaleUp:
  stabilizationWindowSeconds: 120

# Adjust thresholds
metrics:
  target:
    averageValue: "70"  # Add buffer from oscillation point
```

#### Slow Scaling Response
**Symptoms**: Takes too long to scale up during demand spikes
**Causes**:
- Long stabilization windows
- Conservative scaling policies
- Resource quotas

**Solutions**:
```yaml
# More aggressive scale-up
scaleUp:
  policies:
  - periodSeconds: 15    # Faster evaluation
    type: Pods
    value: 3            # More pods per scaling event
  stabilizationWindowSeconds: 30
```

## Future Enhancements

The autoscaling infrastructure is designed to support future enhancements:

### Machine Learning-Based Scaling
- Historical pattern analysis
- Predictive scaling based on data pipeline schedules
- Anomaly detection for unusual workload patterns

### Multi-Cloud Scaling Orchestration
- Cross-cloud load balancing
- Cost-optimized cloud selection
- Disaster recovery scaling

### Advanced Resource Management
- GPU scaling for ML workloads
- Storage scaling for data-intensive operations
- Network bandwidth optimization

## Conclusion

The Matillion Agent Deployment repository provides enterprise-grade autoscaling that goes beyond basic CPU/memory metrics. By using application-specific metrics like active task count and request count, the system makes intelligent scaling decisions that:

- **Reduce costs** by avoiding over-provisioning
- **Improve performance** by scaling proactively to demand
- **Increase reliability** through intelligent stabilization policies
- **Support growth** with flexible, configurable scaling behaviors

Whether you're processing small datasets or running enterprise-scale data pipelines, the autoscaling capabilities ensure your Matillion agents are right-sized for the workload while optimizing for both performance and cost.

Ready to implement intelligent autoscaling? Start with the Kubernetes deployment for the most advanced features, or choose AWS ECS or Azure AKS based on your existing infrastructure preferences.