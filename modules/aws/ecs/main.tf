locals {
  # Fargate-valid (cpu, memory) pairs — see https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-cpu-memory-error.html
  runner_size_map = {
    small  = { cpu = 1024, memory = 4096 }
    medium = { cpu = 2048, memory = 8192 }
    large  = { cpu = 4096, memory = 16384 }
    xlarge = { cpu = 8192, memory = 32768 }
  }

  runner_cpu    = coalesce(var.runner_cpu, local.runner_size_map[var.runner_size].cpu)
  runner_memory = coalesce(var.runner_memory, local.runner_size_map[var.runner_size].memory)

  script_runner_cpu    = local.runner_size_map[var.script_runner_size].cpu
  script_runner_memory = local.runner_size_map[var.script_runner_size].memory
}

resource "aws_s3_bucket" "staging_bucket" {
  count = var.create_bucket == true ? 1 : 0

  bucket = lower(join("-", [var.name, "stagging-bucket"]))
  tags   = var.tags
}

resource "aws_s3_bucket_policy" "staging_bucket_policy" {
  count = var.create_bucket == true ? 1 : 0

  bucket = aws_s3_bucket.staging_bucket[count.index].bucket
  policy = templatefile("${path.module}/templates/s3_policy.json.tmpl", {
    account_root = data.aws_caller_identity.this.account_id
    iam_role_arn = var.runner_task_role_execution_arn
    bucket_name  = aws_s3_bucket.staging_bucket[count.index].bucket
  })

}

resource "aws_security_group" "ecs_security_group" {
  name        = join("-", [var.name, "matillion-runner-security-group"])
  description = "Allow http to client host"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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

resource "aws_cloudwatch_log_group" "matillion_dpc_runner_task_logs" {

  name              = "/ecs/${var.name}-task"
  retention_in_days = 30
  tags = merge(
    var.tags,
    {
      Name = "/ecs/${var.name}-task"
    }
  )
}

resource "aws_ecs_task_definition" "matillion_dpc_runner" {

  family = join("-", [var.name, "task"])

  container_definitions = templatefile("${path.module}/templates/matillion-task-definition.json.tmpl", {
    name                       = join("-", [var.name, "task-definition"])
    image                      = var.image_url
    log_group                  = aws_cloudwatch_log_group.matillion_dpc_runner_task_logs.name
    account_id                 = var.account_id
    agent_id                   = var.agent_id
    matillion_region           = var.matillion_region
    matillion_environment      = var.matillion_environment
    extension_library_location = var.extension_library_location
    proxy_http                 = var.proxy_http
    proxy_https                = var.proxy_https
    proxy_excludes             = var.proxy_excludes
    custom_cert_location       = var.custom_cert_location
    external_driver_location   = var.external_driver_location
    export_logs                = var.export_logs
    runner_secret_arn          = var.runner_secret_arn
    region                     = var.region
    version_consistency        = "disabled"
  })

  task_role_arn      = var.runner_task_role_arn
  execution_role_arn = var.runner_task_role_execution_arn

  requires_compatibilities = ["FARGATE"]
  memory                   = local.runner_memory
  cpu                      = local.runner_cpu
  network_mode             = "awsvpc"
  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  # Volumes for writable directories when using read-only root filesystem
  # Fargate doesn't support tmpfs, so using regular volumes
  volume { name = "tmp-volume" }
  volume { name = "api-profiles-volume" }
  volume { name = "cdata-volume" }
  volume { name = "cache-volume" }
  volume { name = "python-libs-volume" }
  volume { name = "jdbc-drivers-volume" }
  volume { name = "custom-certs-volume" }

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

  name            = join("-", [var.name, "service"])
  cluster         = aws_ecs_cluster.matillion_dpc_cluster.id
  task_definition = aws_ecs_task_definition.matillion_dpc_runner.arn
  desired_count   = var.desired_count

  # When Service Connect is enabled, ensure the script-runner is healthy and its
  # alias is registered in the namespace before launching agent tasks. ECS Service
  # Connect proxy sidecars snapshot the namespace at task launch — an agent that
  # starts before the script-runner alias exists will never resolve "script-runner"
  # until the agent tasks are redeployed.
  depends_on = [aws_ecs_service.script_runner]

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    base              = 0
    weight            = 1
  }

  scheduling_strategy = "REPLICA"


  deployment_controller {
    type = "ECS"
  }

  platform_version = "LATEST"

  network_configuration {
    security_groups = concat(
      sort([aws_security_group.ecs_security_group.id]),
      sort(var.security_group_ids)
    )
    subnets          = var.subnet_ids
    assign_public_ip = var.assign_public_ip
  }

  deployment_minimum_healthy_percent = 50

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # No service{} block: the agent joins the namespace as a client only (to resolve script-runner:2222
  # via Service Connect DNS) without registering itself as a discoverable service.
  service_connect_configuration {
    enabled   = var.enable_script_runner
    namespace = var.enable_script_runner ? aws_service_discovery_http_namespace.cluster_namespace[0].arn : null
  }
  tags = merge(
    var.tags,
    {
      Name = join("-", [var.name, "service"])
    }
  )
}

# ── Script runner resources (enable_script_runner = true) ──────────────────────

resource "aws_service_discovery_http_namespace" "cluster_namespace" {
  count = var.enable_script_runner ? 1 : 0
  name  = join("-", [var.name, "service-connect"])
  tags  = var.tags
}

resource "aws_security_group" "script_runner_security_group" {
  count = var.enable_script_runner ? 1 : 0

  name        = join("-", [var.name, "script-runner-sg"])
  description = "Allow SSH from agent to maia-script-runner"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 2222
    to_port         = 2222
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_security_group.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = join("-", [var.name, "script-runner-sg"])
  })
}

resource "aws_cloudwatch_log_group" "script_runner_task_logs" {
  count = var.enable_script_runner ? 1 : 0

  name              = "/ecs/${var.name}-script-runner-task"
  retention_in_days = var.script_runner_log_retention_days
  tags = merge(var.tags, {
    Name = "/ecs/${var.name}-script-runner-task"
  })
}

resource "aws_ecs_task_definition" "script_runner" {
  count = var.enable_script_runner ? 1 : 0

  family = join("-", [var.name, "script-runner-task"])

  container_definitions = templatefile("${path.module}/templates/maia-script-runner-task-definition.json.tmpl", {
    name                       = var.name
    image                      = var.script_runner_image_url
    log_group                  = aws_cloudwatch_log_group.script_runner_task_logs[0].name
    keypair_secret_arn         = var.runner_keypair_secret_arn
    extension_library_location = var.extension_library_location
    region                     = var.region
  })

  task_role_arn      = var.script_runner_task_role_arn
  execution_role_arn = var.runner_task_role_execution_arn

  requires_compatibilities = ["FARGATE"]
  memory                   = local.script_runner_memory
  cpu                      = local.script_runner_cpu
  network_mode             = "awsvpc"
  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  tags = merge(var.tags, {
    Name = join("-", [var.name, "script-runner-task"])
  })

  lifecycle {
    precondition {
      condition     = var.runner_keypair_secret_arn != ""
      error_message = "runner_keypair_secret_arn must be set when enable_script_runner is true."
    }
    precondition {
      condition     = var.script_runner_task_role_arn != ""
      error_message = "script_runner_task_role_arn must be set when enable_script_runner is true."
    }
  }
}

resource "aws_ecs_service" "script_runner" {
  count = var.enable_script_runner ? 1 : 0

  name            = join("-", [var.name, "script-runner"])
  cluster         = aws_ecs_cluster.matillion_dpc_cluster.id
  task_definition = aws_ecs_task_definition.script_runner[0].arn
  desired_count   = var.script_runner_desired_count

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    base              = 0
    weight            = 1
  }

  scheduling_strategy = "REPLICA"

  deployment_controller {
    type = "ECS"
  }

  platform_version = "LATEST"

  network_configuration {
    security_groups  = [aws_security_group.script_runner_security_group[0].id]
    subnets          = var.subnet_ids
    assign_public_ip = var.assign_public_ip
  }

  deployment_minimum_healthy_percent = 100

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.cluster_namespace[0].arn
    service {
      port_name = "ssh"
      client_alias {
        dns_name = "script-runner"
        port     = 2222
      }
    }
  }

  # Block until the script-runner alias is live in the namespace before Terraform
  # considers this resource complete. Without this, the agent service (which depends_on
  # this resource) could launch its proxy sidecars before the alias is registered,
  # causing UnknownHostException on every connection attempt.
  wait_for_steady_state = true

  tags = merge(var.tags, {
    Name = join("-", [var.name, "script-runner"])
  })
}
