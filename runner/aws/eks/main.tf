# Description: This file is the main entry point for the EKS module. It creates the EKS cluster and the associated resources.
module "deployment" {
  source = "../../../modules/aws/deployment"

  use_existing_vpc    = var.use_existing_vpc
  existing_vpc_id     = var.existing_vpc_id
  use_existing_subnet = var.use_existing_subnet

  name               = var.name
  cidr_block         = var.cidr_block
  random_string_salt = random_string.salt.result
  tags               = var.tags
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
  endpoint_public_access  = !var.is_private_cluster
  endpoint_private_access = var.is_private_cluster
  public_access_cidrs     = var.authorized_ip_ranges
}
# ---------------------------------------------------------------------------
# Optional SQS -> DPC pipeline-execution Lambda adapter ("Option A").
# ---------------------------------------------------------------------------
module "sqs_dpc_adapter" {
  count  = var.enable_sqs_pipeline_trigger ? 1 : 0
  source = "../../../modules/aws/lambda/sqs-dpc-adapter"

  name_prefix = join("-", [var.name, "maia-sqs-adapter"])
  aws_region  = var.region
  image_uri   = var.sqs_adapter_image_uri
  secret_name = var.sqs_adapter_secret_name

  create_queue       = var.sqs_adapter_create_queue
  queue_name         = var.sqs_adapter_queue_name
  existing_queue_arn = var.sqs_adapter_existing_queue_arn
  existing_queue_url = var.sqs_adapter_existing_queue_url

  create_mapping_table        = var.sqs_adapter_create_mapping_table
  mapping_table_name          = var.sqs_adapter_mapping_table_name
  existing_mapping_table_name = var.sqs_adapter_existing_mapping_table_name
  existing_mapping_table_arn  = var.sqs_adapter_existing_mapping_table_arn

  matillion_api_url   = var.sqs_adapter_matillion_api_url
  matillion_token_url = var.sqs_adapter_matillion_token_url

  tags = var.tags
}
