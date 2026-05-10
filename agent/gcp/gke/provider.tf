# GCP Provider Configuration for GKE Deployment
provider "google" {
  project = var.project_id
  region  = var.region
}
