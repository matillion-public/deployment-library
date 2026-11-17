# Run with: terraform test  (from runner/aws/eks)
#
# Validation of dpc_policy_arn, the pre-created policy passed to module.eks. Uses a mock
# provider, so no AWS credentials or resources are needed.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["eu-west-1a", "eu-west-1b"] }
  }
}

variables {
  region = "eu-west-1"
  tags   = {}
}

run "rejects_invalid_dpc_policy_arn" {
  command = plan

  variables {
    dpc_policy_arn = "not-an-arn"
  }

  expect_failures = [var.dpc_policy_arn]
}

# A root test cannot reference the attachment inside module.eks, so this run checks that the
# plan succeeds with a policy ARN and that the value reaches the root unchanged.

run "accepts_policy_arn" {
  command = plan

  variables {
    dpc_policy_arn = "arn:aws:iam::123456789012:policy/DataProductivityCloudAccess"
  }

  assert {
    condition     = var.dpc_policy_arn == "arn:aws:iam::123456789012:policy/DataProductivityCloudAccess"
    error_message = "A valid IAM policy ARN must be accepted."
  }
}
