output "network_id" {
  value = google_compute_network.vpc.id
}

output "network_name" {
  value = google_compute_network.vpc.name
}

output "subnet_ids" {
  value = [for subnet in google_compute_subnetwork.subnets : subnet.id]
}

output "subnet_names" {
  value = [for subnet in google_compute_subnetwork.subnets : subnet.name]
}

output "pod_secondary_range_name" {
  value = google_compute_subnetwork.subnets[0].secondary_ip_range[0].range_name
}

output "services_secondary_range_name" {
  value = google_compute_subnetwork.subnets[0].secondary_ip_range[1].range_name
}

output "nat_ip" {
  value = var.enable_cloud_nat ? google_compute_address.nat_ip[0].address : null
}
