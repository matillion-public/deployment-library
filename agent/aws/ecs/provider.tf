# AWS Provider Configuration for ECS Deployment
provider "aws" {
  region = var.region
  shared_credentials_files = ["/deployment-assets/credentials.env"]
  
  # Add default tags for all resources
  default_tags {
    tags = {
      ManagedBy    = "Terraform"
      DeploymentType = "ECS"
      Project      = "MatillionAgent"
    }
  }
}