output "network_id" {
  value = local.network_id
}

output "network_name" {
  value = local.create_network ? google_compute_network.vpc[0].name : null
}

output "subnet_ids" {
  value = [local.subnet_id]
}

output "subnet_names" {
  value = [for subnet in google_compute_subnetwork.subnets : subnet.name]
}

output "pod_secondary_range_name" {
  value = local.pod_secondary_range_name
}

output "services_secondary_range_name" {
  value = local.services_secondary_range_name
}

output "nat_ip" {
  value = var.enable_cloud_nat ? google_compute_address.nat_ip[0].address : null
}
