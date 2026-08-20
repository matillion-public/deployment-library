terraform {
  required_version = "~> 1.5"
  required_providers {
    # This module serves BOTH the AWS and GCP composer contracts, which share
    # the `modules/core/networking-vpc` path. The active cloud is selected with
    # var.cloud; the other provider's resources are count-gated to zero.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}
