# Run with: terraform test  (from runner/aws/ecs)
#
# Subnet CIDR selection in an existing VPC stays the same on applies after the first. Uses a mock provider, so no AWS
# credentials or resources are needed.

mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = { cidr_block = "172.31.0.0/16" }
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
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/t" }
  }
}

override_resource {
  target          = random_string.salt
  override_during = plan
  values          = { id = "abc123", result = "abc123" }
}

variables {
  name                = "t"
  region              = "eu-west-1"
  account_id          = "00000000-0000-0000-0000-000000000000"
  agent_id            = "00000000-0000-0000-0000-000000000001"
  image_url           = "example.com/runner:latest"
  client_id           = "id"
  client_secret       = "secret"
  use_existing_vpc    = true
  vpc_id              = "vpc-00000000000000001"
  use_existing_subnet = false
}

run "subnets_from_other_deployments_are_avoided" {
  command = plan

  override_data {
    target = data.aws_subnets.existing_in_vpc
    values = { ids = ["subnet-default-a", "subnet-default-b", "subnet-default-c", "subnet-other-0"] }
  }

  override_data {
    target = data.aws_subnet.existing_details["subnet-default-a"]
    values = { cidr_block = "172.31.0.0/20", tags = {} }
  }

  override_data {
    target = data.aws_subnet.existing_details["subnet-default-b"]
    values = { cidr_block = "172.31.16.0/20", tags = {} }
  }

  override_data {
    target = data.aws_subnet.existing_details["subnet-default-c"]
    values = { cidr_block = "172.31.32.0/20", tags = {} }
  }

  override_data {
    target = data.aws_subnet.existing_details["subnet-other-0"]
    values = { cidr_block = "172.31.48.0/24", tags = { Name = "other-xyz789-ecs-subnet-0" } }
  }

  assert {
    condition     = aws_subnet.ecs_subnet[0].cidr_block == "172.31.49.0/24"
    error_message = "A subnet created by another deployment must not be reused."
  }

  assert {
    condition     = aws_subnet.ecs_subnet[1].cidr_block == "172.31.50.0/24"
    error_message = "A subnet created by another deployment must not be reused."
  }
}

run "first_apply" {
  command = apply

  override_data {
    target = data.aws_subnets.existing_in_vpc
    values = { ids = ["subnet-default-a", "subnet-default-b", "subnet-default-c"] }
  }

  override_data {
    target = data.aws_subnet.existing_details["subnet-default-a"]
    values = { cidr_block = "172.31.0.0/20", tags = {} }
  }

  override_data {
    target = data.aws_subnet.existing_details["subnet-default-b"]
    values = { cidr_block = "172.31.16.0/20", tags = {} }
  }

  override_data {
    target = data.aws_subnet.existing_details["subnet-default-c"]
    values = { cidr_block = "172.31.32.0/20", tags = {} }
  }

  assert {
    condition     = aws_subnet.ecs_subnet[0].cidr_block == "172.31.48.0/24"
    error_message = "The first free /24 in the VPC must be selected."
  }

  assert {
    condition     = aws_subnet.ecs_subnet[1].cidr_block == "172.31.49.0/24"
    error_message = "The second free /24 in the VPC must be selected."
  }
}

run "second_plan_keeps_own_subnets" {
  command = plan

  override_data {
    target = data.aws_subnets.existing_in_vpc
    values = { ids = ["subnet-default-a", "subnet-default-b", "subnet-default-c", "subnet-own-0", "subnet-own-1"] }
  }

  override_data {
    target = data.aws_subnet.existing_details["subnet-default-a"]
    values = { cidr_block = "172.31.0.0/20", tags = {} }
  }

  override_data {
    target = data.aws_subnet.existing_details["subnet-default-b"]
    values = { cidr_block = "172.31.16.0/20", tags = {} }
  }

  override_data {
    target = data.aws_subnet.existing_details["subnet-default-c"]
    values = { cidr_block = "172.31.32.0/20", tags = {} }
  }

  override_data {
    target = data.aws_subnet.existing_details["subnet-own-0"]
    values = { cidr_block = "172.31.48.0/24", tags = { Name = "t-abc123-ecs-subnet-0" } }
  }

  override_data {
    target = data.aws_subnet.existing_details["subnet-own-1"]
    values = { cidr_block = "172.31.49.0/24", tags = { Name = "t-abc123-ecs-subnet-1" } }
  }

  assert {
    condition     = aws_subnet.ecs_subnet[0].cidr_block == "172.31.48.0/24"
    error_message = "The first subnet's CIDR block must not change on a later apply."
  }

  assert {
    condition     = aws_subnet.ecs_subnet[1].cidr_block == "172.31.49.0/24"
    error_message = "The second subnet's CIDR block must not change on a later apply."
  }
}

run "own_subnets_on_later_blocks_are_kept" {
  command = plan

  override_data {
    target = data.aws_subnets.existing_in_vpc
    values = { ids = ["subnet-default-a", "subnet-default-b", "subnet-default-c", "subnet-own-0", "subnet-own-1"] }
  }

  override_data {
    target = data.aws_subnet.existing_details["subnet-default-a"]
    values = { cidr_block = "172.31.0.0/20", tags = {} }
  }

  override_data {
    target = data.aws_subnet.existing_details["subnet-default-b"]
    values = { cidr_block = "172.31.16.0/20", tags = {} }
  }

  override_data {
    target = data.aws_subnet.existing_details["subnet-default-c"]
    values = { cidr_block = "172.31.32.0/20", tags = {} }
  }

  override_data {
    target = data.aws_subnet.existing_details["subnet-own-0"]
    values = { cidr_block = "172.31.50.0/24", tags = { Name = "t-abc123-ecs-subnet-0" } }
  }

  override_data {
    target = data.aws_subnet.existing_details["subnet-own-1"]
    values = { cidr_block = "172.31.51.0/24", tags = { Name = "t-abc123-ecs-subnet-1" } }
  }

  assert {
    condition     = aws_subnet.ecs_subnet[0].cidr_block == "172.31.50.0/24"
    error_message = "The first subnet must keep its CIDR block when a lower block is free."
  }

  assert {
    condition     = aws_subnet.ecs_subnet[1].cidr_block == "172.31.51.0/24"
    error_message = "The second subnet must keep its CIDR block when a lower block is free."
  }
}

run "missing_own_subnet_takes_a_free_block" {
  command = plan

  override_data {
    target = data.aws_subnets.existing_in_vpc
    values = { ids = ["subnet-default-a", "subnet-default-b", "subnet-default-c", "subnet-own-0"] }
  }

  override_data {
    target = data.aws_subnet.existing_details["subnet-default-a"]
    values = { cidr_block = "172.31.0.0/20", tags = {} }
  }

  override_data {
    target = data.aws_subnet.existing_details["subnet-default-b"]
    values = { cidr_block = "172.31.16.0/20", tags = {} }
  }

  override_data {
    target = data.aws_subnet.existing_details["subnet-default-c"]
    values = { cidr_block = "172.31.32.0/20", tags = {} }
  }

  override_data {
    target = data.aws_subnet.existing_details["subnet-own-0"]
    values = { cidr_block = "172.31.48.0/24", tags = { Name = "t-abc123-ecs-subnet-0" } }
  }

  assert {
    condition     = aws_subnet.ecs_subnet[0].cidr_block == "172.31.48.0/24"
    error_message = "The existing subnet must keep its CIDR block."
  }

  assert {
    condition     = aws_subnet.ecs_subnet[1].cidr_block == "172.31.49.0/24"
    error_message = "The missing subnet must take the first free block, not one the existing subnet holds."
  }
}

run "existing_subnets_in_a_small_vpc_plan" {
  command = plan

  variables {
    use_existing_subnet = true
    subnet_ids          = ["subnet-customer-0", "subnet-customer-1"]
  }

  override_data {
    target = data.aws_vpc.vpc
    values = { cidr_block = "10.0.0.0/26" }
  }

  assert {
    condition     = length(aws_subnet.ecs_subnet) == 0
    error_message = "No subnets must be created when existing subnets are supplied."
  }
}
