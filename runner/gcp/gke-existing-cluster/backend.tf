# GCS Backend Configuration for GKE Deployment
terraform {
  # Uncomment and fill in to use GCS for remote state. One state per runner, so
  # every runner sharing a cluster keeps its own prefix.
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "gke/<cluster_name>/<name>"
  # }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  required_version = ">= 1.2"
}
