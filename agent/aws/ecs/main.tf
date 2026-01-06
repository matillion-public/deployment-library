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
}

data "aws_vpc" "vpc" {
  id = local.vpc_id
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
  cidr_block              = cidrsubnet(data.aws_vpc.vpc.cidr_block, 8, 0 + count.index)
  availability_zone       = element(random_shuffle.aws_availability_zone_names.result, count.index)
  map_public_ip_on_launch = true
  tags = merge(var.tags, {
    Name = join("-", [var.name, random_string.salt.result, "ecs", "subnet", count.index])
  })
}

resource "aws_route_table_association" "ecs_subnet_association" {
  count          = var.use_existing_subnet ? 0 : 2
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
