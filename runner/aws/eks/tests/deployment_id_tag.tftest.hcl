# Run with: terraform test  (from runner/aws/eks)
#
# The matillion:deployment-id tag as wired through the root. Uses a mock provider, so no AWS
# credentials or resources are needed. Provider default_tags are not visible to a mock plan.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["eu-west-1a", "eu-west-1b"] }
  }
}

variables {
  name   = "t"
  region = "eu-west-1"
}

run "deployment_id_tag_reaches_kms_key" {
  command = plan

  variables {
    tags = { Owner = "team" }
  }

  assert {
    condition     = module.eks.kms_key_tags["matillion:deployment-id"] == "t"
    error_message = "The KMS key must carry matillion:deployment-id = name."
  }

  assert {
    condition     = module.eks.kms_key_tags["Owner"] == "team"
    error_message = "var.tags must still reach the KMS key."
  }

  assert {
    condition     = local.tags["matillion:deployment-id"] == "t"
    error_message = "local.tags must carry matillion:deployment-id = name."
  }
}

run "deployment_id_tag_overrides_customer_value" {
  command = plan

  variables {
    tags = { "matillion:deployment-id" = "other" }
  }

  assert {
    condition     = module.eks.kms_key_tags["matillion:deployment-id"] == "t"
    error_message = "name must override a matillion:deployment-id value in var.tags on the KMS key."
  }

  assert {
    condition     = local.tags["matillion:deployment-id"] == "t"
    error_message = "name must override a matillion:deployment-id value in var.tags in local.tags."
  }
}
