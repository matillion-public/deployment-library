# A Matillion runner in a GKE cluster that already exists, beside any other runners
# in it. Nothing here changes the cluster. Each runner gets its own Google service
# accounts, bound through Workload Identity only to the Kubernetes service accounts
# named after it, and can read and update only secrets whose IDs start with its own
# prefix. The runner chart creates the namespace and Kubernetes service accounts
# when installed with the outputs (with serviceAccount.create=false, create them
# yourself under these names); runner/helm/README.md "Shared Multi-Tenant
# Platform" shows how, and how to add the namespace to the cluster's Prometheus.

# Workload Identity binds a Kubernetes service account to a Google one through
# the cluster's pool. Without it the binding below names a pool that doesn't
# exist, and the pods quietly run as the node's service account instead.
data "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.location
  project  = var.project_id

  lifecycle {
    postcondition {
      condition     = try(self.workload_identity_config[0].workload_pool, "") == "${var.project_id}.svc.id.goog"
      error_message = "Cluster ${var.cluster_name} doesn't have Workload Identity enabled with workload pool ${var.project_id}.svc.id.goog. Enable it first: gcloud container clusters update ${var.cluster_name} --location ${var.location} --workload-pool=${var.project_id}.svc.id.goog"
    }
  }
}

locals {
  namespace                          = var.name
  service_account_name               = "${var.name}-sa"
  script_runner_service_account_name = "${var.name}-script-runner-sa"
  secret_name_prefix                 = "matillion_${var.name}_"
}

module "identity" {
  source = "../../../modules/gcp/runner-identity"

  name                 = var.name
  project_id           = var.project_id
  namespace            = local.namespace
  service_account_name = local.service_account_name
  secret_name_prefix   = local.secret_name_prefix
  storage_bucket_names = var.storage_bucket_names
}

# The script runner runs code people write, so it gets a service account of its
# own: the same buckets, and no secrets. With the runner's, a script could read
# and overwrite every secret the runner keeps, OAuth tokens included.
module "script_runner_identity" {
  source = "../../../modules/gcp/runner-identity"

  name                 = "${var.name}-scripts"
  project_id           = var.project_id
  namespace            = local.namespace
  service_account_name = local.script_runner_service_account_name
  storage_bucket_names = var.storage_bucket_names

  resource_names = {
    runner_service_account = "${var.name}-scripts"
  }
}
