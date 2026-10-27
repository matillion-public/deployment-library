# Run with: terraform test  (from modules/aws/deployment)
#
# Availability zone selection. Uses a mock provider, so no AWS credentials or resources are needed.

mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = { cidr_block = "10.0.0.0/16" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b"] }
  }
}

variables {
  use_existing_vpc   = false
  existing_vpc_id    = ""
  name               = "t"
  cidr_block         = "10.0.0.0/16"
  tags               = {}
  random_string_salt = "abc123"
}

run "excludes_zones_without_eks_control_plane_support" {
  command = plan

  assert {
    condition     = toset(data.aws_availability_zones.available.exclude_zone_ids) == toset(["use1-az3", "usw1-az2", "cac1-az3"])
    error_message = "Zones that cannot host an EKS control plane must be excluded from selection."
  }
}
