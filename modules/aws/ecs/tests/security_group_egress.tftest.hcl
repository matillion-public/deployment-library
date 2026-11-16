# Run with: terraform test  (from modules/aws/ecs)
#
# The runner security group allows all outbound traffic unless the caller
# supplies groups that carry the egress rules (allow_all_egress = false).
# Runs share state, so the last run applies allow_all_egress = false over a
# group that already has the allow-all rule, as an upgraded deployment does.
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
  security_group_ids             = ["sg-0customer00000000"]
  runner_task_role_execution_arn = "arn:aws:iam::123456789012:role/exec"
  runner_task_role_arn           = "arn:aws:iam::123456789012:role/task"
  runner_secret_arn              = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:runner"
}

run "no_egress_when_disabled" {
  command = apply

  variables {
    allow_all_egress = false
  }

  assert {
    condition     = length(aws_security_group.ecs_security_group.egress) == 0
    error_message = "The runner security group must have no egress rule when allow_all_egress is false."
  }

  assert {
    condition     = aws_ecs_service.matillion_dpc_service.network_configuration[0].security_groups == toset(["sg-0runner0000000000", "sg-0customer00000000"])
    error_message = "The service should still attach the runner security group and the supplied groups."
  }
}

run "all_traffic_egress_by_default" {
  command = apply

  assert {
    condition     = length(aws_security_group.ecs_security_group.egress) == 1
    error_message = "The runner security group should have exactly one egress rule by default."
  }

  assert {
    condition = alltrue([
      for rule in aws_security_group.ecs_security_group.egress :
      rule.protocol == "-1" && rule.from_port == 0 && rule.to_port == 0 && rule.cidr_blocks == tolist(["0.0.0.0/0"])
    ])
    error_message = "The default egress rule should allow all traffic to 0.0.0.0/0."
  }
}

run "existing_egress_removed_when_disabled" {
  command = apply

  variables {
    allow_all_egress = false
  }

  assert {
    condition     = length(aws_security_group.ecs_security_group.egress) == 0
    error_message = "Setting allow_all_egress to false must remove the allow-all rule from an existing runner security group."
  }
}
