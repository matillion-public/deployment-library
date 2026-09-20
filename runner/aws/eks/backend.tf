# S3 Backend Configuration for EKS Deployment
terraform {
  # Uncomment and fill in to use S3 for remote state. Take bucket, region and
  # dynamodb_table from modules/aws/state-management's backend_config output rather
  # than rebuilding them from account_id — resource_names can change either name,
  # and a mismatch here fails terraform init.
  # backend "s3" {
  #   bucket         = "<state_management.backend_config.bucket>"
  #   key            = "eks/<region>/<cluster_name>/terraform.tfstate"
  #   region         = "<state_management.backend_config.region>"
  #   dynamodb_table = "<state_management.backend_config.dynamodb_table>"
  #   encrypt        = true
  # }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  required_version = ">= 1.0"
}