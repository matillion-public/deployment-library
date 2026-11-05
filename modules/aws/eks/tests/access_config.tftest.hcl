# Run with: terraform test  (from modules/aws/eks)
#
# Cluster authentication mode and access entries. Uses mock providers, so no AWS
# credentials or resources are needed.

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

run "defaults_to_api_and_config_map" {
  command = plan

  assert {
    condition     = aws_eks_cluster.eks_cluster.access_config[0].authentication_mode == "API_AND_CONFIG_MAP"
    error_message = "The cluster must default to API_AND_CONFIG_MAP so access entries are usable."
  }

  assert {
    condition     = length(aws_eks_access_entry.admin) == 0
    error_message = "No access entries are created unless principals are supplied."
  }
}

run "bootstraps_cluster_creator_admin_permissions" {
  command = plan

  assert {
    condition     = aws_eks_cluster.eks_cluster.access_config[0].bootstrap_cluster_creator_admin_permissions == true
    error_message = "bootstrap_cluster_creator_admin_permissions must be true. Unset, the provider sends false on create and plans a replacement of clusters created before access_config was set."
  }
}

run "creates_cluster_admin_entries_for_supplied_principals" {
  command = plan

  variables {
    additional_admin_principal_arns = [
      "arn:aws:iam::123456789012:role/platform-team",
      "arn:aws:iam::123456789012:role/ci",
    ]
  }

  assert {
    condition     = length(aws_eks_access_entry.admin) == 2
    error_message = "One access entry is expected per supplied principal."
  }

  assert {
    condition = alltrue([
      for a in aws_eks_access_policy_association.admin :
      a.policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" && a.access_scope[0].type == "cluster"
    ])
    error_message = "Each principal must receive AmazonEKSClusterAdminPolicy at cluster scope."
  }
}

run "rejects_admin_principals_in_config_map_mode" {
  command = plan

  variables {
    authentication_mode             = "CONFIG_MAP"
    additional_admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-team"]
  }

  expect_failures = [aws_eks_access_entry.admin]
}

run "rejects_unknown_authentication_mode" {
  command = plan

  variables {
    authentication_mode = "OIDC"
  }

  expect_failures = [var.authentication_mode]
}
