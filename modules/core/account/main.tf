# modules/core/account
#
# Provider-agnostic root configuration. Declares the target account /
# subscription / project and region for a deployment. This module intentionally
# provisions NO cloud resources — it is the composer's "account" contract and
# exists so downstream compute/auth/networking modules can consume a single,
# validated source of region + target-account values.

locals {
  # The target-account identifier for whichever cloud is selected. Downstream
  # modules read `target_account` rather than the cloud-specific inputs.
  target_account = coalesce(
    var.cloud == "aws" ? var.aws_account_id : null,
    var.cloud == "azure" ? var.azure_subscription_id : null,
    var.cloud == "gcp" ? var.gcp_project_id : null,
    "default"
  )
}
