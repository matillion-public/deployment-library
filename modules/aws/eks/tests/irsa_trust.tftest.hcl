# Run with: terraform test  (from modules/aws/eks)
#
# Which service accounts can assume the runner's IRSA role. Uses mock providers,
# so no AWS credentials or resources are needed. The cluster's OIDC issuer and the provider's
# ARN are computed, so they are overridden to be known at plan time.

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
  name                    = "t"
  region                  = "eu-west-1"
  subnet_ids              = ["subnet-00000000000000001"]
  security_group_ids      = ["sg-0000000000000001"]
  endpoint_private_access = true
  endpoint_public_access  = false
  public_access_cidrs     = ["203.0.113.0/24"]
  random_string_salt      = "abc123"
  tags                    = {}
}

run "role_trusts_only_the_default_service_accounts_in_the_matillion_namespace" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_role.service_account_role.assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.eu-west-1.amazonaws.com/id/ABC123:sub"] == [
      "system:serviceaccount:matillion:matillion-runner-sa",
      "system:serviceaccount:matillion:matillion-runner-script-runner-sa",
    ]
    error_message = "The role must trust exactly the runner and script runner service accounts in the matillion namespace."
  }
}

run "role_trusts_the_service_accounts_it_is_given" {
  command = plan

  variables {
    namespace                          = "finance"
    service_account_name               = "finance-sa"
    script_runner_service_account_name = "finance-script-runner-sa"
  }

  assert {
    condition = jsondecode(aws_iam_role.service_account_role.assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.eu-west-1.amazonaws.com/id/ABC123:sub"] == [
      "system:serviceaccount:finance:finance-sa",
      "system:serviceaccount:finance:finance-script-runner-sa",
    ]
    error_message = "The role must trust exactly the named service accounts, in the given namespace."
  }
}

run "role_trust_has_no_wildcard_and_no_string_like" {
  command = plan

  assert {
    condition     = !strcontains(aws_iam_role.service_account_role.assume_role_policy, "*")
    error_message = "The trust policy must not contain a wildcard."
  }

  assert {
    condition     = !contains(keys(jsondecode(aws_iam_role.service_account_role.assume_role_policy).Statement[0].Condition), "StringLike")
    error_message = "The trust policy must use StringEquals, not StringLike."
  }
}

run "role_trust_requires_the_sts_audience" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.service_account_role.assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.eu-west-1.amazonaws.com/id/ABC123:aud"] == "sts.amazonaws.com"
    error_message = "The trust policy must require the sts.amazonaws.com audience."
  }
}

run "fargate_profile_selects_the_default_namespace" {
  command = plan

  assert {
    condition     = contains([for s in aws_eks_fargate_profile.fargate_profile.selector : s.namespace], "matillion")
    error_message = "The Fargate profile must schedule the default namespace."
  }
}

run "fargate_profile_selects_the_namespace_it_is_given" {
  command = plan

  variables {
    namespace = "finance"
  }

  assert {
    condition     = contains([for s in aws_eks_fargate_profile.fargate_profile.selector : s.namespace], "finance")
    error_message = "The Fargate profile must schedule the namespace the role trusts."
  }

  assert {
    condition     = !contains([for s in aws_eks_fargate_profile.fargate_profile.selector : s.namespace], "matillion")
    error_message = "The Fargate profile must not keep selecting the default namespace once another is given."
  }
}
