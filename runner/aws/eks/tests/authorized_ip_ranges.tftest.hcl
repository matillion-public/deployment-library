# Run with: terraform test  (from runner/aws/eks)
#
# Which CIDR blocks reach the cluster's public API endpoint. Uses a mock provider, so
# no AWS credentials or resources are needed.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["eu-west-1a", "eu-west-1b"] }
  }
}

variables {
  region = "eu-west-1"
  tags   = {}
}

run "public_endpoint_requires_authorized_ip_ranges" {
  command = plan

  variables {
    is_private_cluster = false
  }

  expect_failures = [random_string.salt]
}

run "public_endpoint_rejects_an_empty_list" {
  command = plan

  variables {
    is_private_cluster   = false
    authorized_ip_ranges = []
  }

  expect_failures = [random_string.salt]
}

# The runs below assert on local.public_access_cidrs, the value passed to module.eks. A root test
# cannot reference the cluster resource inside the module, and the module has no output for it.

run "public_endpoint_accepts_given_ranges" {
  command = plan

  variables {
    is_private_cluster   = false
    authorized_ip_ranges = ["203.0.113.0/24"]
  }

  assert {
    condition     = local.public_access_cidrs == tolist(["203.0.113.0/24"])
    error_message = "public_access_cidrs must equal authorized_ip_ranges when it is set."
  }
}

run "public_endpoint_accepts_explicit_open_access" {
  command = plan

  variables {
    is_private_cluster   = false
    authorized_ip_ranges = ["0.0.0.0/0"]
  }

  assert {
    condition     = local.public_access_cidrs == tolist(["0.0.0.0/0"])
    error_message = "public_access_cidrs must equal authorized_ip_ranges when it is set."
  }
}

run "private_cluster_needs_no_authorized_ip_ranges" {
  command = plan

  assert {
    condition     = local.public_access_cidrs == tolist(["0.0.0.0/0"])
    error_message = "public_access_cidrs must fall back to [\"0.0.0.0/0\"] for a private cluster with authorized_ip_ranges unset, so existing private clusters plan no change."
  }
}
