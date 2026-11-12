# Run with: terraform test  (from modules/aws/ecs)
#
# runner_cpu and runner_memory are checked at plan, so an invalid Fargate size fails before any resource is created.
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
}

run "runner_cpu_alone_resolving_to_invalid_pair_fails" {
  command = plan

  variables {
    runner_cpu = 4096
  }

  expect_failures = [aws_ecs_task_definition.matillion_dpc_runner]
}

run "runner_memory_alone_resolving_to_invalid_pair_fails" {
  command = plan

  variables {
    runner_memory = 1024
  }

  expect_failures = [aws_ecs_task_definition.matillion_dpc_runner]
}

run "runner_cpu_alone_resolving_to_valid_pair_is_used" {
  command = plan

  variables {
    runner_size = "medium"
    runner_cpu  = 2048
  }

  assert {
    condition     = aws_ecs_task_definition.matillion_dpc_runner.cpu == "2048" && aws_ecs_task_definition.matillion_dpc_runner.memory == "8192"
    error_message = "runner_cpu alone must combine with the memory from runner_size."
  }
}

run "runner_memory_alone_resolving_to_valid_pair_is_used" {
  command = plan

  variables {
    runner_size   = "large"
    runner_memory = 8192
  }

  assert {
    condition     = aws_ecs_task_definition.matillion_dpc_runner.cpu == "4096" && aws_ecs_task_definition.matillion_dpc_runner.memory == "8192"
    error_message = "runner_memory alone must combine with the CPU from runner_size."
  }
}

run "invalid_fargate_pair_fails" {
  command = plan

  variables {
    runner_cpu    = 4096
    runner_memory = 4096
  }

  expect_failures = [aws_ecs_task_definition.matillion_dpc_runner]
}

run "memory_off_increment_fails" {
  command = plan

  variables {
    runner_cpu    = 8192
    runner_memory = 17408
  }

  expect_failures = [aws_ecs_task_definition.matillion_dpc_runner]
}

run "valid_pair_is_used" {
  command = plan

  variables {
    runner_cpu    = 2048
    runner_memory = 4096
  }

  assert {
    condition     = aws_ecs_task_definition.matillion_dpc_runner.cpu == "2048"
    error_message = "runner_cpu must be used as the task CPU."
  }

  assert {
    condition     = aws_ecs_task_definition.matillion_dpc_runner.memory == "4096"
    error_message = "runner_memory must be used as the task memory."
  }
}

run "largest_size_is_valid" {
  command = plan

  variables {
    runner_size = "xlarge"
  }

  assert {
    condition     = aws_ecs_task_definition.matillion_dpc_runner.cpu == "8192"
    error_message = "runner_size = xlarge must resolve to 8192 CPU."
  }

  assert {
    condition     = aws_ecs_task_definition.matillion_dpc_runner.memory == "32768"
    error_message = "runner_size = xlarge must resolve to 32768 MiB."
  }
}
