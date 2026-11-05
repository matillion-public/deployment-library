# Run with: terraform test  (from modules/aws/ecs)
#
# Opt-in ingress for scraping the runner's Prometheus metrics (DPC-58192).
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

run "no_ingress_by_default" {
  command = plan

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.metrics_from_cidr) == 0
    error_message = "No CIDR ingress rule should exist unless a CIDR is named."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.metrics_from_security_group) == 0
    error_message = "No security-group ingress rule should exist unless a group is named."
  }
}

run "one_rule_per_cidr_and_port" {
  command = plan

  variables {
    metrics_ingress_cidr_blocks = ["10.0.0.0/16", "10.1.0.0/16"]
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.metrics_from_cidr) == 4
    error_message = "Expected 2 CIDRs x 2 default ports = 4 rules."
  }

  assert {
    condition     = toset([for r in aws_vpc_security_group_ingress_rule.metrics_from_cidr : r.from_port]) == toset([9464, 8080])
    error_message = "Default ports should be 9464 (OpenTelemetry) and 8080 (legacy)."
  }

  assert {
    condition     = alltrue([for r in aws_vpc_security_group_ingress_rule.metrics_from_cidr : r.from_port == r.to_port && r.ip_protocol == "tcp"])
    error_message = "Each rule should open exactly one TCP port."
  }
}

run "otel_only" {
  command = plan

  variables {
    metrics_ingress_security_group_ids = ["sg-0prometheus000000"]
    metrics_ingress_ports              = [9464]
  }

  assert {
    condition     = keys(aws_vpc_security_group_ingress_rule.metrics_from_security_group) == ["sg-0prometheus000000:9464"]
    error_message = "Expected a single rule from the Prometheus security group on 9464."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.metrics_from_security_group["sg-0prometheus000000:9464"].referenced_security_group_id == "sg-0prometheus000000"
    error_message = "The rule should reference the named security group."
  }
}

run "rejects_open_internet" {
  command = plan

  variables {
    metrics_ingress_cidr_blocks = ["0.0.0.0/0"]
  }

  expect_failures = [var.metrics_ingress_cidr_blocks]
}

run "rejects_invalid_cidr" {
  command = plan

  variables {
    metrics_ingress_cidr_blocks = ["10.0.0.0"]
  }

  expect_failures = [var.metrics_ingress_cidr_blocks]
}

run "rejects_empty_port_list" {
  command = plan

  variables {
    metrics_ingress_cidr_blocks = ["10.0.0.0/16"]
    metrics_ingress_ports       = []
  }

  expect_failures = [var.metrics_ingress_ports]
}
