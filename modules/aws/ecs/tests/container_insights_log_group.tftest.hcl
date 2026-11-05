# Run with: terraform test  (from modules/aws/ecs)
#
# The Container Insights performance log group is managed so that it is tagged,
# has a retention policy and is removed on destroy.
# Uses a mock provider, so no AWS credentials or resources are needed.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_resource "aws_security_group" {
    defaults = { id = "sg-0runner0000000000" }
  }
}

variables {
  name                           = "t"
  region                         = "eu-west-1"
  account_id                     = "00000000-0000-0000-0000-000000000000"
  agent_id                       = "00000000-0000-0000-0000-000000000001"
  vpc_id                         = "vpc-0000000000000000"
  subnet_ids                     = ["subnet-00000000000000001"]
  security_group_ids             = []
  runner_task_role_execution_arn = "arn:aws:iam::123456789012:role/exec"
  runner_task_role_arn           = "arn:aws:iam::123456789012:role/task"
  runner_secret_arn              = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:runner"
  tags                           = { ManagedBy = "terraform" }
}

run "default_cluster_name" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.container_insights_performance.name == "/aws/ecs/containerinsights/t-cluster/performance"
    error_message = "Log group name should be derived from the default cluster name."
  }

  assert {
    condition     = aws_cloudwatch_log_group.container_insights_performance.name == "/aws/ecs/containerinsights/${aws_ecs_cluster.matillion_dpc_cluster.name}/performance"
    error_message = "Log group name must match the cluster that Container Insights writes for."
  }

  assert {
    condition     = aws_cloudwatch_log_group.container_insights_performance.retention_in_days == 30
    error_message = "Log group must have a retention policy."
  }

  assert {
    condition     = aws_cloudwatch_log_group.container_insights_performance.tags["ManagedBy"] == "terraform"
    error_message = "Log group must carry the caller's tags."
  }

  assert {
    condition     = aws_cloudwatch_log_group.container_insights_performance.tags["Name"] == aws_cloudwatch_log_group.container_insights_performance.name
    error_message = "Log group Name tag must equal its name."
  }
}

run "overridden_cluster_name" {
  command = plan

  variables {
    resource_names = { ecs_cluster = "custom-cluster" }
  }

  assert {
    condition     = aws_cloudwatch_log_group.container_insights_performance.name == "/aws/ecs/containerinsights/custom-cluster/performance"
    error_message = "Log group name should follow a cluster name override."
  }
}
