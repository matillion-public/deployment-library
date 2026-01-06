# S3 Backend Configuration for EKS Deployment
terraform {
  # backend "s3" {
  #   # Bucket will be dynamically configured during deployment
  #   # bucket = "${account_id}-terraform-states"
  #   # key    = "eks/${region}/${cluster_name}/terraform.tfstate"
  #   # region = "${region}"
    
  #   # Enable encryption
  #   encrypt        = true
    
  #   # DynamoDB table for state locking
  #   # dynamodb_table = "terraform-state-locks"
  # }
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  required_version = ">= 1.0"
}