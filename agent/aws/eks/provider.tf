# AWS Provider Configuration for EKS Deployment
provider "aws" {
  region = var.region
  
  # Add default tags for all resources
  default_tags {
    tags = {
      ManagedBy    = "Terraform"
      DeploymentType = "EKS"
      Project      = "MatillionAgent"
    }
  }
}