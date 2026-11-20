# Run with: terraform test  (from modules/aws/eks)
#
# Which IAM policy the IRSA role receives: the per-deployment policy the module creates,
# or a pre-created policy supplied by ARN. Uses mock providers, so no AWS credentials or
# resources are needed.

mock_provider "aws" {}

mock_provider "tls" {
  mock_data "tls_certificate" {
    defaults = {
      certificates = [{ sha1_fingerprint = "0123456789abcdef0123456789abcdef01234567" }]
    }
  }
}

override_resource {
  target          = aws_eks_cluster.eks_cluster
  override_during = plan
  values = {
    identity = [{
      oidc = [{ issuer = "https://oidc.eks.eu-west-1.amazonaws.com/id/ABC123" }]
    }]
  }
}

override_resource {
  target          = aws_iam_openid_connect_provider.eks
  override_during = plan
  values = {
    arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-west-1.amazonaws.com/id/ABC123"
  }
}

variables {
  name                   = "t"
  region                 = "eu-west-1"
  subnet_ids             = ["subnet-00000000000000001"]
  security_group_ids     = ["sg-0000000000000001"]
  endpoint_public_access = false
  public_access_cidrs    = ["203.0.113.0/24"]
  random_string_salt     = "abc123"
  tags                   = {}
}

run "default_creates_and_attaches_own_policy" {
  command = plan

  # The mock provider leaves arn unknown at plan, so the attachment's policy_arn would be unknown too.
  override_resource {
    target          = aws_iam_policy.dpc_policy
    override_during = plan
    values = {
      arn = "arn:aws:iam::123456789012:policy/DataProductivityCloudAccess-abc123"
    }
  }

  assert {
    condition     = length(aws_iam_policy.dpc_policy) == 1
    error_message = "With dpc_policy_arn unset, the module must create its own policy."
  }

  assert {
    condition     = aws_iam_policy.dpc_policy[0].name == "DataProductivityCloudAccess-abc123"
    error_message = "The module-created policy must keep the DataProductivityCloudAccess-<salt> name."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.service_account_dpc_policy.policy_arn == "arn:aws:iam::123456789012:policy/DataProductivityCloudAccess-abc123"
    error_message = "With dpc_policy_arn unset, the IRSA role must receive the module-created policy."
  }
}

run "supplied_arn_skips_policy_and_attaches_it" {
  command = plan

  variables {
    dpc_policy_arn = "arn:aws:iam::123456789012:policy/DataProductivityCloudAccess"
  }

  assert {
    condition     = length(aws_iam_policy.dpc_policy) == 0
    error_message = "With dpc_policy_arn set, the module must not create a policy."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.service_account_dpc_policy.policy_arn == "arn:aws:iam::123456789012:policy/DataProductivityCloudAccess"
    error_message = "With dpc_policy_arn set, the IRSA role must receive the supplied policy."
  }
}

run "rejects_non_policy_arn" {
  command = plan

  variables {
    dpc_policy_arn = "arn:aws:iam::123456789012:role/DataProductivityCloudAccess"
  }

  expect_failures = [var.dpc_policy_arn]
}

run "rejects_bare_name" {
  command = plan

  variables {
    dpc_policy_arn = "DataProductivityCloudAccess"
  }

  expect_failures = [var.dpc_policy_arn]
}
