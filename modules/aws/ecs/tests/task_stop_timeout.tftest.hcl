# Run with: terraform test  (from modules/aws/ecs)
#
# The runner container gets the Fargate maximum stop timeout of 120 seconds to
# drain in-flight pipeline tasks, instead of the 30-second default.
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

run "runner_container_stop_timeout" {
  command = plan

  assert {
    condition     = jsondecode(aws_ecs_task_definition.matillion_dpc_runner.container_definitions)[0].stopTimeout == 120
    error_message = "Runner container must set stopTimeout to the Fargate maximum of 120 seconds."
  }
}
