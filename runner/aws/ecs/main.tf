resource "random_string" "salt" {
  length           = 6
  special          = false
  override_special = "/@£$"
}

# VPC and Networking Resources
resource "aws_vpc" "main_vpc" {
  count = var.use_existing_vpc ? 0 : 1

  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(var.tags, {
    Name = join("-", [var.name, random_string.salt.result, "vpc"])
  })
}

locals {
  vpc_id                     = var.use_existing_vpc ? var.vpc_id : aws_vpc.main_vpc[0].id
  runner_keypair_secret_name = var.runner_keypair_secret_name != "" ? var.runner_keypair_secret_name : join("-", [var.name, "runner-keypair"])
}

data "aws_vpc" "vpc" {
  id = local.vpc_id
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Look up existing subnets to avoid CIDR conflicts when creating subnets in an existing VPC
data "aws_subnets" "existing_in_vpc" {
  count = var.use_existing_vpc && !var.use_existing_subnet ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

data "aws_subnet" "existing_details" {
  for_each = var.use_existing_vpc && !var.use_existing_subnet ? toset(try(data.aws_subnets.existing_in_vpc[0].ids, [])) : toset([])
  id       = each.value
}

locals {
  existing_subnet_cidrs = [for s in data.aws_subnet.existing_details : s.cidr_block]

  # CIDR overlap detection using IP-to-integer arithmetic (Terraform-compatible, no cidrcontains)
  vpc_prefix_len = tonumber(split("/", data.aws_vpc.vpc.cidr_block)[1])
  candidate_size = pow(2, 32 - local.vpc_prefix_len - 8)

  vpc_start_int = (
    tonumber(element(split(".", cidrhost(data.aws_vpc.vpc.cidr_block, 0)), 0)) * pow(2, 24) +
    tonumber(element(split(".", cidrhost(data.aws_vpc.vpc.cidr_block, 0)), 1)) * pow(2, 16) +
    tonumber(element(split(".", cidrhost(data.aws_vpc.vpc.cidr_block, 0)), 2)) * pow(2, 8) +
    tonumber(element(split(".", cidrhost(data.aws_vpc.vpc.cidr_block, 0)), 3))
  )

  existing_subnet_ranges = [
    for cidr in local.existing_subnet_cidrs : {
      start = (
        tonumber(element(split(".", cidrhost(cidr, 0)), 0)) * pow(2, 24) +
        tonumber(element(split(".", cidrhost(cidr, 0)), 1)) * pow(2, 16) +
        tonumber(element(split(".", cidrhost(cidr, 0)), 2)) * pow(2, 8) +
        tonumber(element(split(".", cidrhost(cidr, 0)), 3))
      )
      size = pow(2, 32 - tonumber(split("/", cidr)[1]))
    }
  ]

  # Find netnums that don't overlap with any existing subnet (handles different prefix lengths)
  available_netnums = [
    for n in range(0, 256) : n
    if !anytrue([
      for existing in local.existing_subnet_ranges :
      (local.vpc_start_int + n * local.candidate_size) < (existing.start + existing.size) &&
      existing.start < (local.vpc_start_int + n * local.candidate_size + local.candidate_size)
    ])
  ]

  subnet_netnums = var.use_existing_vpc && !var.use_existing_subnet ? (
    length(local.available_netnums) >= 2 ? slice(local.available_netnums, 0, 2) : error("Insufficient available CIDR blocks in VPC. Found ${length(local.available_netnums)} available netnums, need at least 2.")
  ) : [0, 1]
}

resource "random_shuffle" "aws_availability_zone_names" {
  input        = data.aws_availability_zones.available.names
  result_count = 2
}

resource "aws_internet_gateway" "igw" {
  count = var.use_existing_vpc ? 0 : 1

  vpc_id = data.aws_vpc.vpc.id
  tags = merge(var.tags, {
    Name = join("-", [var.name, random_string.salt.result, "igw"])
  })
}

resource "aws_route_table" "public" {
  count = var.use_existing_vpc ? 0 : 1

  vpc_id = data.aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw[count.index].id
  }
  tags = merge(var.tags, {
    Name = join("-", [var.name, random_string.salt.result, "public", "route", "table"])
  })
}

resource "aws_subnet" "ecs_subnet" {
  count = var.use_existing_subnet ? 0 : 2

  vpc_id                  = data.aws_vpc.vpc.id
  cidr_block              = cidrsubnet(data.aws_vpc.vpc.cidr_block, 8, local.subnet_netnums[count.index])
  availability_zone       = element(random_shuffle.aws_availability_zone_names.result, count.index)
  map_public_ip_on_launch = true
  tags = merge(var.tags, {
    Name = join("-", [var.name, random_string.salt.result, "ecs", "subnet", count.index])
  })
}

data "aws_route_table" "existing" {
  count  = var.use_existing_vpc && !var.use_existing_subnet ? 1 : 0
  vpc_id = var.vpc_id

  filter {
    name   = "association.main"
    values = ["true"]
  }
}

resource "aws_route_table_association" "ecs_subnet_association" {
  count          = var.use_existing_subnet ? 0 : 2
  subnet_id      = element(aws_subnet.ecs_subnet[*].id, count.index)
  route_table_id = var.use_existing_vpc ? data.aws_route_table.existing[0].id : aws_route_table.public[0].id
}

resource "aws_security_group" "ecs_security_group" {
  count = var.use_existing_security_group ? 0 : 1

  name        = join("-", [var.name, random_string.salt.result, "ecs", "sg"])
  description = "Security group for ECS tasks"
  vpc_id      = data.aws_vpc.vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = join("-", [var.name, random_string.salt.result, "ecs", "sg"])
  })
}

module "secert_manager" {
  source = "../../../modules/aws/secerts-manager"

  name        = join("-", [var.name, random_string.salt.result])
  secret_name = var.secret_name

  client_id     = var.client_id
  client_secret = var.client_secret

  enable_keypair_secret      = var.enable_script_runner
  runner_keypair_secret_name = local.runner_keypair_secret_name
  runner_authorized_keys     = var.runner_authorized_keys
}

module "iam_roles" {
  source = "../../../modules/aws/iam"

  name              = join("-", [var.name, random_string.salt.result])
  runner_secret_arn = module.secert_manager.runner_secret_arn

  enable_script_runner                       = var.enable_script_runner
  runner_keypair_secret_arn                  = module.secert_manager.runner_keypair_secret_arn
  script_runner_extension_library_bucket_arn = var.script_runner_extension_library_bucket_arn
}

module "runner" {
  source = "../../../modules/aws/ecs"

  name = join("-", [var.name, random_string.salt.result])

  account_id            = var.account_id
  agent_id              = var.agent_id
  matillion_region      = var.matillion_region
  matillion_environment = var.matillion_environment

  region             = var.region
  vpc_id             = data.aws_vpc.vpc.id
  subnet_ids         = var.use_existing_subnet ? var.subnet_ids : aws_subnet.ecs_subnet[*].id
  security_group_ids = var.use_existing_security_group ? var.security_group_ids : [aws_security_group.ecs_security_group[0].id]
  create_bucket      = var.create_bucket
  image_url          = var.image_url

  extension_library_location = var.extension_library_location
  proxy_http                 = var.proxy_http
  proxy_https                = var.proxy_https
  proxy_excludes             = var.proxy_excludes
  custom_cert_location       = var.custom_cert_location
  external_driver_location   = var.external_driver_location
  export_logs                = var.export_logs

  runner_task_role_arn           = module.iam_roles.ecs_task_role_arn
  runner_task_role_execution_arn = module.iam_roles.ecs_task_execution_role

  runner_secret_arn = module.secert_manager.runner_secret_arn
  desired_count     = var.desired_count

  runner_size   = var.runner_size
  runner_cpu    = var.runner_cpu
  runner_memory = var.runner_memory

  assign_public_ip       = var.assign_public_ip
  ephemeral_storage_size = var.ephemeral_storage_size
  tags                   = var.tags

  enable_script_runner             = var.enable_script_runner
  script_runner_image_url          = var.script_runner_image_url
  script_runner_size               = var.script_runner_size
  script_runner_desired_count      = var.script_runner_desired_count
  script_runner_log_retention_days = var.script_runner_log_retention_days
  runner_keypair_secret_arn        = module.secert_manager.runner_keypair_secret_arn
  script_runner_task_role_arn      = module.iam_roles.script_runner_task_role_arn
}

# module "saturation_monitor" {
#   source = "./saturation-monitor"

#   name                         = var.name
#   cloudwatch_namespace         = "ECS/RunnerSaturation"
#   schedule_expression          = "rate(1 minute)"
#   log_level                    = "INFO"
#   create_dashboard             = true
#   create_alarms                = true
#   high_task_count_threshold    = 50
#   high_request_count_threshold = 20
#   alarm_actions                = []
#   runner_service_indicators    = join(",", ["matillion", "runner", "agent", "dpc", var.name])
# }
