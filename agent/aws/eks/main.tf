# Description: This file is the main entry point for the EKS module. It creates the EKS cluster and the associated resources.
module "deployment" {
  source = "../../../modules/aws/deployment"

  use_existing_vpc    = var.use_existing_vpc
  existing_vpc_id     = var.existing_vpc_id
  use_existing_subnet = var.use_existing_subnet

  name                = var.name
  cidr_block          = var.cidr_block
  random_string_salt  = random_string.salt.result
  tags                = var.tags
}

module "eks" {
  source = "../../../modules/aws/eks"

  name                    = var.name
  region                  = var.region
  random_string_salt      = random_string.salt.result
  subnet_ids              = var.use_existing_subnet ? var.existing_subnet_ids : module.deployment.all_subnet_ids
  fargate_subnet_ids      = var.use_existing_subnet ? var.existing_subnet_ids : module.deployment.private_subnet_ids
  security_group_ids      = [module.deployment.k8s_security_group_id]
  tags                    = var.tags
  endpoint_private_access = var.is_private_cluster
  endpoint_public_access  = !var.is_private_cluster
  public_access_cidrs     = var.authorized_ip_ranges
}