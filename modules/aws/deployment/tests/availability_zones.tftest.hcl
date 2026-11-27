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

run "subnets_in_own_vpc_take_cidrs_from_the_managed_vpc" {
  command = plan

  variables {
    cidr_block = "10.1.0.0/16"
  }

  assert {
    condition     = [for s in aws_subnet.public_subnet : s.cidr_block] == ["10.1.0.0/24", "10.1.1.0/24"]
    error_message = "Public subnet CIDRs in the deployment's own VPC must be known at plan, or a VPC tag change replaces the subnets."
  }

  assert {
    condition     = [for s in aws_subnet.private_subnet : s.cidr_block] == ["10.1.2.0/24", "10.1.3.0/24"]
    error_message = "Private subnet CIDRs in the deployment's own VPC must be known at plan, or a VPC tag change replaces the subnets."
  }
}
