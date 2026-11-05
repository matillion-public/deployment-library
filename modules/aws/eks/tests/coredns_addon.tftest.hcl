# Run with: terraform test  (from modules/aws/eks)
#
# CoreDNS addon configuration. Uses mock providers, so no AWS credentials or resources
# are needed. The cluster's OIDC issuer and the provider's ARN are computed, so they are
# overridden to be known at plan time.

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

run "coredns_addon_adopts_an_existing_self_managed_deployment" {
  command = plan

  assert {
    condition     = aws_eks_addon.coredns.addon_name == "coredns"
    error_message = "CoreDNS must be managed as the coredns EKS addon."
  }

  assert {
    condition     = aws_eks_addon.coredns.resolve_conflicts_on_create == "OVERWRITE"
    error_message = "The addon must overwrite the existing CoreDNS deployment, or creation fails on clusters whose CoreDNS was patched by earlier module versions."
  }
}

run "coredns_addon_tolerates_the_fargate_taint" {
  command = plan

  assert {
    condition = anytrue([
      for t in jsondecode(aws_eks_addon.coredns.configuration_values).tolerations :
      t.key == "eks.amazonaws.com/compute-type" && t.value == "fargate" && t.effect == "NoSchedule" && t.operator == "Equal"
    ])
    error_message = "The CoreDNS addon must tolerate the eks.amazonaws.com/compute-type=fargate:NoSchedule taint."
  }
}
