# Run with: terraform test  (from runner/aws/ecs)
#
# The matillion:deployment-id tag as wired through the root. Uses a mock provider, so no AWS
# credentials or resources are needed. Provider default_tags are not visible to a mock plan.

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

run "deployment_id_tag_is_set" {
  command = plan

  variables {
    tags = { Owner = "team" }
  }

  assert {
    condition     = aws_vpc.main_vpc[0].tags["matillion:deployment-id"] == "t"
    error_message = "The VPC must carry matillion:deployment-id = name."
  }

  assert {
    condition     = aws_vpc.main_vpc[0].tags["Owner"] == "team"
    error_message = "var.tags must still reach the VPC."
  }

  assert {
    condition     = aws_vpc.main_vpc[0].tags["Name"] == "t-abc123-vpc"
    error_message = "The VPC Name tag must be unchanged."
  }

  assert {
    condition     = module.secrets_manager.runner_secret_tags["matillion:deployment-id"] == "t"
    error_message = "The OAuth secret must carry matillion:deployment-id = name."
  }

  assert {
    condition     = module.secrets_manager.runner_secret_tags["Owner"] == "team"
    error_message = "var.tags must still reach the OAuth secret."
  }
}

run "deployment_id_tag_overrides_customer_value" {
  command = plan

  variables {
    tags = { "matillion:deployment-id" = "other" }
  }

  assert {
    condition     = aws_vpc.main_vpc[0].tags["matillion:deployment-id"] == "t"
    error_message = "name must override a matillion:deployment-id value in var.tags on the VPC."
  }

  assert {
    condition     = module.secrets_manager.runner_secret_tags["matillion:deployment-id"] == "t"
    error_message = "name must override a matillion:deployment-id value in var.tags on the OAuth secret."
  }
}
