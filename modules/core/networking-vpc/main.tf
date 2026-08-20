# modules/core/networking-vpc  (AWS and GCP — shared composer path)
#
# Both the AWS and GCP composer contracts declare their networking module at
# `modules/core/networking-vpc`. Rather than fork the path, this single module
# serves both providers via var.cloud and count-gated resources. It references
# an existing VPC/network + subnets (bring-your-own) and emits the least-
# privilege permission set a deploying principal needs, per the contract.
#
# See core/networking-vnet for the Azure equivalent (separate path).

locals {
  is_aws = var.cloud == "aws"
  is_gcp = var.cloud == "gcp"
}

# --- AWS: least-privilege deployer policy -----------------------------------
data "aws_iam_policy_document" "deployer" {
  count = local.is_aws ? 1 : 0

  statement {
    sid    = "NetworkDiscovery"
    effect = "Allow"
    actions = [
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
    ]
    # Describe* actions do not support resource-level permissions.
    resources = ["*"]
  }
  statement {
    sid       = "ServiceDiscovery"
    effect    = "Allow"
    actions   = ["servicediscovery:CreateService"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "deployer" {
  count       = local.is_aws && var.create_deployer_policy ? 1 : 0
  name        = "${var.deployment_name}-networking-vpc-deployer"
  description = "Least-privilege permissions to provision the core/networking-vpc module (AWS)."
  policy      = data.aws_iam_policy_document.deployer[0].json
  tags        = var.tags
}

# --- GCP: least-privilege deployer custom role ------------------------------
resource "google_project_iam_custom_role" "deployer" {
  count       = local.is_gcp && var.create_deployer_policy ? 1 : 0
  project     = var.project_id
  role_id     = replace("${var.deployment_name}_networking_vpc_deployer", "-", "_")
  title       = "${var.deployment_name} networking-vpc deployer"
  description = "Least-privilege permissions to provision the core/networking-vpc module (GCP)."
  permissions = [
    "compute.networks.get",
    "compute.subnetworks.get",
  ]
}
