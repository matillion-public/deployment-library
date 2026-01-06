# ECS Agent Saturation Monitor - Testing Deployment

This optional deployment creates a Lambda function to monitor ECS agent task saturation and publish metrics to CloudWatch.

## Quick Start

1. **Copy the example configuration:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit your configuration:**
   ```bash
   # Edit terraform.tfvars with your specific values
   vim terraform.tfvars
   
   # IMPORTANT: You must configure vpc_config with the same VPC/subnets as your ECS tasks
   # Example:
   vpc_config = {
     vpc_id             = "vpc-12345678"                          # Your VPC ID
     subnet_ids         = ["subnet-12345678", "subnet-87654321"]  # Your ECS task subnets
     security_group_ids = []  # Leave empty to auto-create
   }
   ```

3. **Deploy:**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

## Configuration

### Required Variables
- `name` - Name prefix for all resources
- `vpc_config` - VPC configuration for Lambda to access ECS tasks (required for connectivity)

### Optional Variables
- `cloudwatch_namespace` - CloudWatch namespace (default: "ECS/AgentSaturation")
- `schedule_expression` - How often to run (default: "rate(1 minute)")
- `log_level` - Lambda logging level (default: "INFO")
- `agent_service_indicators` - Service name patterns to match (default: "matillion,agent,dpc")

### Testing Configuration
For initial testing, the defaults include:
- `create_dashboard = true` - Creates CloudWatch dashboard
- `create_alarms = false` - Disables alarms for testing
- `schedule_expression = "rate(1 minute)"` - Runs every minute

## Testing Steps

### 1. Deploy and Verify
```bash
# Deploy the Lambda function
terraform apply

# Check the Lambda was created
aws lambda get-function --function-name $(terraform output -raw lambda_function_name)

# Manually invoke to test
aws lambda invoke --function-name $(terraform output -raw lambda_function_name) --payload '{}' response.json
cat response.json
```

### 2. Check CloudWatch Logs
```bash
# View Lambda execution logs
aws logs tail $(terraform output -raw cloudwatch_log_group_name) --follow
```

### 3. Verify Metrics
```bash
# List published metrics
aws cloudwatch list-metrics --namespace "ECS/AgentSaturation"

# Get recent metric data
aws cloudwatch get-metric-statistics \
    --namespace "ECS/AgentSaturation" \
    --metric-name "ActiveTaskCount" \
    --start-time $(date -d '1 hour ago' --iso-8601) \
    --end-time $(date --iso-8601) \
    --period 300 \
    --statistics Average
```

### 4. View Dashboard
```bash
# Get dashboard URL
terraform output dashboard_url
```

## Troubleshooting

### Lambda Can't Connect to AWS APIs (Connection Timeout)
If you see "Connect timeout on endpoint URL" errors:

1. **VPC Endpoints (Recommended)**:
   ```hcl
   # In terraform.tfvars
   create_vpc_endpoints = true  # Creates ECS, CloudWatch, Logs endpoints
   ```

2. **Alternative: NAT Gateway**:
   ```hcl
   # If you have NAT Gateway for internet access
   create_vpc_endpoints = false
   ```

3. **Check VPC configuration**:
   ```bash
   # Verify Lambda is in correct VPC/subnets
   aws lambda get-function --function-name YOUR_FUNCTION_NAME
   ```

### Lambda Not Finding Services
If the Lambda isn't discovering your ECS services:

1. **Check service naming patterns:**
   ```bash
   # List your ECS services
   aws ecs list-clusters
   aws ecs list-services --cluster YOUR_CLUSTER_NAME
   ```

2. **Update agent_service_indicators:**
   ```hcl
   # In terraform.tfvars
   agent_service_indicators = "your-actual-service-name,another-pattern"
   ```

3. **Check Lambda logs:**
   ```bash
   aws logs tail /aws/lambda/YOUR_FUNCTION_NAME --follow
   ```

### No Metrics Appearing
If metrics aren't appearing in CloudWatch:

1. **Check agent endpoints are accessible:**
   - Lambda needs network access to ECS tasks
   - Tasks must expose actuator endpoint on port 8080

2. **Verify actuator endpoint format:**
   - Lambda tries: `http://PRIVATE_IP:8080/actuator/info`
   - Ensure your agent exposes this endpoint

3. **Check Lambda execution logs:**
   ```bash
   aws logs filter-log-events \
       --log-group-name /aws/lambda/YOUR_FUNCTION_NAME \
       --filter-pattern "ERROR"
   ```

## Production Deployment

When ready for production:

1. **Enable alarms:**
   ```hcl
   create_alarms = true
   alarm_actions = ["arn:aws:sns:region:account:your-topic"]
   ```

2. **Adjust thresholds:**
   ```hcl
   high_task_count_threshold    = 100  # Adjust based on your workload
   high_request_count_threshold = 50   # Adjust based on your workload
   ```

3. **Consider schedule frequency:**
   ```hcl
   schedule_expression = "rate(2 minutes)"  # Reduce frequency if needed
   ```

## Cleanup

To remove all resources:
```bash
terraform destroy
```

## Integration with Main ECS Deployment

To integrate this with your main ECS deployment, add this module call to your main Terraform configuration:

```hcl
module "saturation_monitor" {
  source = "./agent/aws/ecs/saturation-monitor"
  
  name                     = var.name
  agent_service_indicators = "matillion,agent,dpc"
  create_alarms           = true
  alarm_actions           = [aws_sns_topic.alerts.arn]
}
```