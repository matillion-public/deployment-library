# GCS Backend Configuration for GKE Deployment
terraform {
  # Uncomment the backend block below to use GCS for remote state
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "gke/terraform.tfstate"
  # }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  required_version = ">= 1.0"
}
