# Run with: terraform test  (from runner/aws/ecs)
#
# Inputs that AWS would reject partway through apply are rejected at plan instead.
# Invalid runner_cpu/runner_memory combinations are covered in modules/aws/ecs/tests/runner_size_validation.tftest.hcl,
# because expect_failures cannot reference a resource inside a child module.
# Uses a mock provider, so no AWS credentials or resources are needed.

mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = { cidr_block = "10.0.0.0/16" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["eu-west-1a", "eu-west-1b", "eu-west-1c"] }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_data "aws_subnets" {
    defaults = { ids = [] }
  }
}

override_resource {
  target          = random_string.salt
  override_during = plan
  values          = { result = "abc123" }
}

variables {
  name          = "t"
  region        = "eu-west-1"
  account_id    = "00000000-0000-0000-0000-000000000000"
  agent_id      = "00000000-0000-0000-0000-000000000001"
  image_url     = "example.com/runner:latest"
  client_id     = "id"
  client_secret = "secret"
}

run "valid_runner_cpu_and_memory_pair_plans" {
  command = plan

  variables {
    runner_cpu    = 2048
    runner_memory = 4096
  }
}

run "cidr_block_smaller_than_slash_20_fails" {
  command = plan

  variables {
    cidr_block = "10.0.0.0/24"
  }

  expect_failures = [var.cidr_block]
}

run "cidr_block_that_is_not_a_cidr_fails" {
  command = plan

  variables {
    cidr_block = "10.0.0.0"
  }

  expect_failures = [var.cidr_block]
}

run "cidr_block_slash_20_plans" {
  command = plan

  variables {
    cidr_block = "10.0.0.0/20"
  }

  assert {
    condition     = aws_vpc.main_vpc[0].cidr_block == "10.0.0.0/20"
    error_message = "A /20 cidr_block must be accepted."
  }
}

run "existing_vpc_smaller_than_slash_20_fails" {
  command = plan

  variables {
    use_existing_vpc = true
    vpc_id           = "vpc-0000000000000000"
  }

  override_data {
    target = data.aws_vpc.vpc
    values = { cidr_block = "10.0.0.0/24" }
  }

  expect_failures = [aws_subnet.ecs_subnet]
}

run "existing_vpc_slash_20_plans" {
  command = plan

  variables {
    use_existing_vpc = true
    vpc_id           = "vpc-0000000000000000"
  }

  override_data {
    target = data.aws_vpc.vpc
    values = { cidr_block = "10.0.0.0/20" }
  }

  assert {
    condition     = aws_subnet.ecs_subnet[0].cidr_block == "10.0.0.0/28"
    error_message = "A /20 existing VPC must yield /28 subnets."
  }
}

run "name_longer_than_33_characters_fails" {
  command = plan

  variables {
    name = "abcdefghijklmnopqrstuvwxyzabcdefgh"
  }

  expect_failures = [var.name]
}

run "name_of_33_characters_plans" {
  command = plan

  variables {
    name = "abcdefghijklmnopqrstuvwxyzabcdefg"
  }
}
