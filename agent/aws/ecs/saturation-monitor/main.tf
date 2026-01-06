# ECS Agent Saturation Monitor - Optional Lambda deployment for testing

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Call the Lambda saturation monitor module
module "saturation_monitor" {
  source = "../../../../modules/aws/lambda/saturation-monitor"
  
  name                           = var.name
  cloudwatch_namespace          = var.cloudwatch_namespace
  schedule_expression           = var.schedule_expression
  log_level                     = var.log_level
  create_dashboard              = var.create_dashboard
  create_alarms                 = var.create_alarms
  high_task_count_threshold     = var.high_task_count_threshold
  high_request_count_threshold  = var.high_request_count_threshold
  alarm_actions                 = var.alarm_actions
  agent_service_indicators      = var.agent_service_indicators
  vpc_config                    = var.vpc_config
  create_vpc_endpoints          = var.create_vpc_endpoints
  deployment_mode               = var.deployment_mode
  create_internet_access_rules     = var.create_internet_access_rules
  vpc_endpoint_private_dns_enabled = var.vpc_endpoint_private_dns_enabled
}