# Run with: terraform test  (from modules/aws/ecs)
#
# Both ECS services copy their tags to the tasks they start and add the ECS managed
# tags, so the running Fargate tasks carry the deployment's tags.
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

run "runner_service_propagates_tags" {
  command = plan

  variables {
    enable_script_runner = false
  }

  assert {
    condition     = aws_ecs_service.matillion_dpc_service.propagate_tags == "SERVICE"
    error_message = "Runner service must propagate its tags to tasks."
  }

  assert {
    condition     = aws_ecs_service.matillion_dpc_service.enable_ecs_managed_tags == true
    error_message = "Runner service must enable ECS managed tags."
  }

  assert {
    condition     = length(aws_ecs_service.script_runner) == 0
    error_message = "Script runner service must not exist when enable_script_runner is false."
  }
}

run "script_runner_service_propagates_tags" {
  command = plan

  variables {
    enable_script_runner        = true
    runner_keypair_secret_arn   = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:keypair"
    script_runner_task_role_arn = "arn:aws:iam::123456789012:role/script-runner"
  }

  assert {
    condition     = aws_ecs_service.matillion_dpc_service.propagate_tags == "SERVICE"
    error_message = "Runner service must propagate its tags to tasks."
  }

  assert {
    condition     = aws_ecs_service.matillion_dpc_service.enable_ecs_managed_tags == true
    error_message = "Runner service must enable ECS managed tags."
  }

  assert {
    condition     = aws_ecs_service.script_runner[0].propagate_tags == "SERVICE"
    error_message = "Script runner service must propagate its tags to tasks."
  }

  assert {
    condition     = aws_ecs_service.script_runner[0].enable_ecs_managed_tags == true
    error_message = "Script runner service must enable ECS managed tags."
  }
}
