# Description: Entry point for the GKE deployment. Creates GCP networking and a GKE cluster.
resource "random_string" "salt" {
  length  = 6
  upper   = false
  numeric = false
  special = false
}

module "networking" {
  source = "../../../modules/gcp/networking"

  name               = var.name
  project_id         = var.project_id
  region             = var.region
  random_string_salt = lower(random_string.salt.result)
  enable_cloud_nat   = var.enable_cloud_nat
  tags               = var.labels
}

module "gke" {
  source = "../../../modules/gcp/gke"

  name               = var.name
  project_id         = var.project_id
  region             = var.region
  random_string_salt = lower(random_string.salt.result)

  network_id                    = module.networking.network_id
  subnet_id                     = module.networking.subnet_ids[0]
  pod_secondary_range_name      = module.networking.pod_secondary_range_name
  services_secondary_range_name = module.networking.services_secondary_range_name

  desired_node_count     = var.desired_node_count
  machine_type           = var.machine_type
  node_disk_size         = var.node_disk_size
  is_private_cluster     = var.is_private_cluster
  master_ipv4_cidr_block = var.master_ipv4_cidr_block
  authorized_ip_ranges   = var.authorized_ip_ranges

  k8s_namespace            = var.k8s_namespace
  k8s_service_account_name = var.k8s_service_account_name
  agent_gcs_buckets        = var.agent_gcs_buckets
  additional_gcp_projects  = var.additional_gcp_projects

  labels = var.labels
}
