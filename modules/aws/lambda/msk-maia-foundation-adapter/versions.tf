terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.28.0 is the first to accept a kafka:// failure destination and a
      # provisioned poller group.
      version = ">= 6.28.0"
    }
  }

  # Cross-variable validations need 1.9.
  required_version = ">= 1.9"
}
