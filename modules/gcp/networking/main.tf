locals {
  create_network = var.existing_network == null
}

resource "google_compute_network" "vpc" {
  count                   = local.create_network ? 1 : 0
  name                    = join("-", [var.name, "vpc", var.random_string_salt])
  auto_create_subnetworks = false
  project                 = var.project_id
}

resource "google_compute_subnetwork" "subnets" {
  count         = local.create_network ? 1 : 0
  name          = join("-", [var.name, "subnet", var.random_string_salt, count.index])
  ip_cidr_range = "10.0.${count.index + 1}.0/24"
  region        = var.region
  network       = google_compute_network.vpc[0].id
  project       = var.project_id

  secondary_ip_range {
    range_name    = join("-", ["pods", count.index])
    ip_cidr_range = "10.${count.index + 1}.0.0/16"
  }

  secondary_ip_range {
    range_name    = join("-", ["services", count.index])
    ip_cidr_range = "10.${count.index + 10}.0.0/20"
  }
}

locals {
  network_id                    = local.create_network ? google_compute_network.vpc[0].id : var.existing_network.network_id
  subnet_id                     = local.create_network ? google_compute_subnetwork.subnets[0].id : var.existing_network.subnet_id
  pod_secondary_range_name      = local.create_network ? google_compute_subnetwork.subnets[0].secondary_ip_range[0].range_name : var.existing_network.pod_secondary_range_name
  services_secondary_range_name = local.create_network ? google_compute_subnetwork.subnets[0].secondary_ip_range[1].range_name : var.existing_network.services_secondary_range_name
}

# --- Cloud NAT for controlled outbound egress with static IP ---

resource "google_compute_router" "nat_router" {
  count   = var.enable_cloud_nat ? 1 : 0
  name    = join("-", [var.name, "nat-router", var.random_string_salt])
  network = local.network_id
  region  = var.region
  project = var.project_id
}

resource "google_compute_address" "nat_ip" {
  count   = var.enable_cloud_nat ? 1 : 0
  name    = join("-", [var.name, "nat-ip", var.random_string_salt])
  region  = var.region
  project = var.project_id
}

resource "google_compute_router_nat" "cloud_nat" {
  count                              = var.enable_cloud_nat ? 1 : 0
  name                               = join("-", [var.name, "cloud-nat", var.random_string_salt])
  router                             = google_compute_router.nat_router[0].name
  region                             = var.region
  project                            = var.project_id
  nat_ip_allocate_option             = "MANUAL_ONLY"
  nat_ips                            = [google_compute_address.nat_ip[0].self_link]
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
