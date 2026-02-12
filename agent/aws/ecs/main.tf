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
  vpc_id = var.use_existing_vpc ? var.vpc_id : aws_vpc.main_vpc[0].id

  # Convert each existing subnet CIDR to a numeric start + size for overlap detection
  existing_ranges = [
    for cidr in [for s in data.aws_subnet.existing : s.cidr_block] : {
      start = (
        tonumber(split(".", split("/", cidr)[0])[0]) * 16777216 +
        tonumber(split(".", split("/", cidr)[0])[1]) * 65536 +
        tonumber(split(".", split("/", cidr)[0])[2]) * 256 +
        tonumber(split(".", split("/", cidr)[0])[3])
      )
      size = pow(2, 32 - tonumber(split("/", cidr)[1]))
    }
  ]

  # Numeric start of the VPC CIDR and size of each candidate subnet
  vpc_ip = split(".", split("/", data.aws_vpc.vpc.cidr_block)[0])
  vpc_start = (
    tonumber(local.vpc_ip[0]) * 16777216 +
    tonumber(local.vpc_ip[1]) * 65536 +
    tonumber(local.vpc_ip[2]) * 256 +
    tonumber(local.vpc_ip[3])
  )
  candidate_size = pow(2, 32 - tonumber(split("/", data.aws_vpc.vpc.cidr_block)[1]) - 8)

  # Find subnet indices whose CIDR range does not overlap any existing subnet
  available_subnet_indices = [
    for i in range(0, 256) : i
    if !anytrue([
      for r in local.existing_ranges :
      (local.vpc_start + i * local.candidate_size) < (r.start + r.size) &&
      r.start < (local.vpc_start + (i + 1) * local.candidate_size)
    ])
  ]
}

data "aws_vpc" "vpc" {
  id = local.vpc_id
}

data "aws_subnets" "existing" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

data "aws_subnet" "existing" {
  for_each = toset(data.aws_subnets.existing.ids)
  id       = each.value
}

data "aws_availability_zones" "available" {
  state = "available"
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
  cidr_block              = cidrsubnet(data.aws_vpc.vpc.cidr_block, 8, local.available_subnet_indices[count.index])
  availability_zone       = element(random_shuffle.aws_availability_zone_names.result, count.index)
  map_public_ip_on_launch = true
  tags = merge(var.tags, {
    Name = join("-", [var.name, random_string.salt.result, "ecs", "subnet", count.index])
  })
}

resource "aws_route_table_association" "ecs_subnet_association" {
  count          = !var.use_existing_subnet && !var.use_existing_vpc ? 2 : 0
  subnet_id      = element(aws_subnet.ecs_subnet[*].id, count.index)
  route_table_id = aws_route_table.public[0].id
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

  name = join("-", [var.name, random_string.salt.result])

  client_id     = var.client_id
  client_secret = var.client_secret
}

module "iam_roles" {
  source = "../../../modules/aws/iam"

  name             = join("-", [var.name, random_string.salt.result])
  agent_secret_arn = module.secert_manager.agent_secret_arn
}

module "agent" {
  source = "../../../modules/aws/ecs"

  name = join("-", [var.name, random_string.salt.result])

  account_id       = var.account_id
  agent_id         = var.agent_id
  matillion_region = var.matillion_region

  region             = var.region
  vpc_id             = data.aws_vpc.vpc.id
  subnet_ids         = var.use_existing_subnet ? var.subnet_ids : aws_subnet.ecs_subnet[*].id
  security_group_ids = var.use_existing_security_group ? var.security_group_ids : [aws_security_group.ecs_security_group[0].id]
  create_bucket      = var.create_bucket

  extension_library_location = var.extension_library_location
  extension_library_protocol = var.extension_library_protocol

  agent_task_role_arn           = module.iam_roles.ecs_task_role_arn
  agent_task_role_execution_arn = module.iam_roles.ecs_task_execution_role

  agent_secret_arn = module.secert_manager.agent_secret_arn
  desired_count    = var.desired_count

  agent_cpu    = var.agent_cpu
  agent_memory = var.agent_memory

  assign_public_ip       = var.assign_public_ip
  ephemeral_storage_size = var.ephemeral_storage_size
  tags                   = var.tags
}

# module "saturation_monitor" {
#   source = "./saturation-monitor"

#   name                         = var.name
#   cloudwatch_namespace         = "ECS/AgentSaturation"
#   schedule_expression          = "rate(1 minute)"
#   log_level                    = "INFO"
#   create_dashboard             = true
#   create_alarms                = true
#   high_task_count_threshold    = 50
#   high_request_count_threshold = 20
#   alarm_actions                = []
#   agent_service_indicators     = join(",", ["matillion", "agent", "dpc", var.name])
# }
