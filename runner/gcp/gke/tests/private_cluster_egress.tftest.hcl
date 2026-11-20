# Run with: terraform test  (from runner/gcp/gke)
#
# Private nodes have no external IPs, so a VPC this root creates needs Cloud NAT
# for the runner to reach Matillion. Uses a mock provider, so no GCP credentials
# or resources are needed.

mock_provider "google" {}

mock_provider "random" {}

# The module's cluster_ca_certificate output indexes the cluster's master_auth
# block, which a mock provider leaves empty and an override can't fill.
override_module {
  target = module.gke
  outputs = {
    cluster_name             = "matillion-runner-gke-cluster-abcdef"
    cluster_endpoint         = "203.0.113.1"
    cluster_ca_certificate   = ""
    runner_workload_sa_email = "runner@runner-project.iam.gserviceaccount.com"
    gcs_bucket_name          = "matillion-runner-staging-abcdef"
    secret_manager_secret_id = "matillion-runner-runner-secret-abcdef"
    auth_config_command      = "gcloud container clusters get-credentials matillion-runner-gke-cluster-abcdef"
  }
}

# Gives the NAT address a known value at plan, so output.nat_ip shows whether
# the NAT resources (router, address, NAT), which share one count, are created.
# A test cannot read resources inside module.networking directly.
override_resource {
  target          = module.networking.google_compute_address.nat_ip
  override_during = plan
  values = {
    address = "203.0.113.10"
  }
}

variables {
  name                 = "matillion-runner"
  project_id           = "runner-project"
  region               = "europe-west1"
  authorized_ip_ranges = ["203.0.113.0/24"]
  labels = {
    environment = "test"
  }
}

run "rejects_private_nodes_without_cloud_nat_in_a_new_vpc" {
  command = plan

  variables {
    is_private_cluster = true
    enable_cloud_nat   = false
  }

  expect_failures = [random_string.salt]
}

run "accepts_private_nodes_without_cloud_nat_in_an_existing_vpc" {
  command = plan

  variables {
    is_private_cluster = true
    enable_cloud_nat   = false
    existing_network = {
      network_id                    = "runner-vpc"
      subnet_id                     = "runner-subnet"
      pod_secondary_range_name      = "pods"
      services_secondary_range_name = "services"
    }
  }

  assert {
    condition     = output.nat_ip == null
    error_message = "With existing_network and enable_cloud_nat = false, no Cloud NAT is created; the VPC provides its own egress."
  }
}

run "accepts_private_nodes_with_cloud_nat" {
  command = plan

  variables {
    is_private_cluster = true
    enable_cloud_nat   = true
  }

  assert {
    condition     = output.nat_ip == "203.0.113.10"
    error_message = "Private nodes with enable_cloud_nat = true must get Cloud NAT with a static egress address."
  }
}

run "accepts_public_nodes_without_cloud_nat" {
  command = plan

  variables {
    is_private_cluster = false
    enable_cloud_nat   = false
  }

  assert {
    condition     = output.nat_ip == null
    error_message = "Public nodes with enable_cloud_nat = false must not get Cloud NAT."
  }
}
