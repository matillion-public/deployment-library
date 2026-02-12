resource "aws_s3_bucket" "staging_bucket" {
  count = var.create_bucket == true ? 1 : 0

  bucket = lower(join("-", [var.name, "stagging-bucket"]))
  tags = var.tags
}

resource "aws_s3_bucket_policy" "staging_bucket_policy" {
  count = var.create_bucket == true ? 1 : 0

  bucket = aws_s3_bucket.staging_bucket[count.index].bucket
  policy = templatefile("${path.module}/templates/s3_policy.json.tmpl", {
    account_root = data.aws_caller_identity.this.account_id
    iam_role_arn = var.agent_task_role_execution_arn
    bucket_name  = aws_s3_bucket.staging_bucket[count.index].bucket
  })
  
}

resource "aws_security_group" "ecs_security_group" {
  name        = join("-", [var.name, "matillion-agent-security-group"])
  description = "Allow http to client host"
  vpc_id      = var.vpc_id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
  tags = var.tags
}

resource "aws_ecs_cluster" "matillion_dpc_cluster" {
  name = join("-", [var.name, "cluster"])

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  configuration {
    execute_command_configuration {
      logging = "DEFAULT"
    }
  }

  tags = merge(
    var.tags,
    {
      Name = join("-", [var.name, "cluster"])
    }
  )
}

resource "aws_cloudwatch_log_group" "matillion_dpc_agent_task_logs" {

  name = "/ecs/${var.name}-task"
  retention_in_days = 30
  tags = merge(
    var.tags,
    {
      Name = "/ecs/${var.name}-task"
    }
  )
}

resource "aws_ecs_task_definition" "matillion_dpc_agent" {

  family = join("-", [var.name, "task"])

  container_definitions = templatefile("${path.module}/templates/matillion-task-definition.json.tmpl", {
    name                        = join("-", [var.name, "task-definition"])
    image                       = var.image_url
    log_group                   = aws_cloudwatch_log_group.matillion_dpc_agent_task_logs.name
    account_id                  = var.account_id
    agent_id                    = var.agent_id
    matillion_region            = var.matillion_region
    matillion_environment       = var.matillion_environment
    extension_library_location  = var.extension_library_location
    extension_library_protocol  = var.extension_library_protocol
    agent_secret_arn            = var.agent_secret_arn
    region                      = var.region
    version_consistency         = "disabled"
  })

  task_role_arn            = var.agent_task_role_arn
  execution_role_arn       = var.agent_task_role_execution_arn
  
  requires_compatibilities = ["FARGATE"]
  memory                   = var.agent_memory
  cpu                      = var.agent_cpu
  network_mode             = "awsvpc"
  runtime_platform {
    cpu_architecture = "X86_64"
    operating_system_family = "LINUX"
  }

  # Volumes for writable directories when using read-only root filesystem
  # Fargate doesn't support tmpfs, so using regular volumes
  volume {
    name = "tmp-volume"
  }

  volume {
    name = "api-profiles-volume"
  }

  # Conditionally include ephemeral storage configuration if size is provided
  dynamic "ephemeral_storage" {
    for_each = var.ephemeral_storage_size != null ? [var.ephemeral_storage_size] : []
    content {
      size_in_gib = ephemeral_storage.value
    }
  }

  tags = merge(
    var.tags,
    {
      Name = join("-", [var.name, "task-definition"])
    }
  )
}

resource "aws_ecs_service" "matillion_dpc_service" {

  name            = join("-",[var.name, "service"])
  cluster         = aws_ecs_cluster.matillion_dpc_cluster.id
  task_definition = aws_ecs_task_definition.matillion_dpc_agent.arn
  desired_count   = var.desired_count

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    base = 0
    weight = 1
  }

  scheduling_strategy = "REPLICA"


  deployment_controller {
    type = "ECS"
  }

  platform_version = "LATEST"

  network_configuration {
    security_groups  = concat(   
      sort([aws_security_group.ecs_security_group.id]),
      sort(var.security_group_ids)
    )
    subnets          = var.subnet_ids
    assign_public_ip = var.assign_public_ip
  }

  wait_for_steady_state              = true
  deployment_minimum_healthy_percent = 50

  deployment_circuit_breaker {
    enable = true
    rollback = true
  }

  service_connect_configuration {
    enabled = false
  }
  tags = merge(
    var.tags,
    {
      Name = join("-", [var.name, "service"])
    }
  )
}