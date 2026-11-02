# Run with: terraform test  (from runner/aws/ecs)
#
# Availability zone selection as wired through the root. Uses a mock provider, so no AWS credentials or resources are needed.

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

run "excludes_zones_without_eks_control_plane_support" {
  command = plan

  assert {
    condition     = toset(data.aws_availability_zones.available.exclude_zone_ids) == toset(["use1-az3", "usw1-az2", "cac1-az3"])
    error_message = "Zones that cannot host an EKS control plane must be excluded from selection."
  }
}
