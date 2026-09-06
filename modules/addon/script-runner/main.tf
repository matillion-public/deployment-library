# modules/addon/script-runner  (AWS / Azure / GCP)
#
# The shared script runner (script pushdown). Declares script_runner as an ECS
# Service / Container App / Cloud Run service per provider, named
# "{deployment_name}-script-runner". The agent reaches it over SSH on port 2222,
# so the runner needs NO cloud IAM permissions of its own.
#
# The script_runner -> agent_service dependency is established by referencing
# var.agent_service_id (surfaced in a tag/label/env), so the runner is created
# after the agent service.

locals {
  is_aws   = var.cloud == "aws"
  is_azure = var.cloud == "azure"
  is_gcp   = var.cloud == "gcp"
  name     = "${var.deployment_name}-script-runner"

  # Referencing agent_service_id here creates the ordering edge to core/compute-*.
  runner_tags = merge(var.tags, { AgentService = var.agent_service_id })

  aws_size_map = {
    small  = { cpu = 1024, memory = 4096 }
    medium = { cpu = 2048, memory = 8192 }
    large  = { cpu = 4096, memory = 16384 }
    xlarge = { cpu = 8192, memory = 32768 }
  }
  azure_size_map = {
    small  = { cpu = 1.0, memory = "4Gi" }
    medium = { cpu = 2.0, memory = "8Gi" }
    large  = { cpu = 4.0, memory = "16Gi" }
    xlarge = { cpu = 8.0, memory = "16Gi" }
  }
  gcp_size_map = {
    small  = { cpu = "1", memory = "4Gi" }
    medium = { cpu = "2", memory = "8Gi" }
    large  = { cpu = "4", memory = "16Gi" }
    xlarge = { cpu = "8", memory = "16Gi" }
  }
}

# --------------------------------------------------------------------------- #
# AWS: ECS Service (reuses the agent's cluster).                              #
# --------------------------------------------------------------------------- #
resource "aws_ecs_task_definition" "script_runner" {
  count                    = local.is_aws ? 1 : 0
  family                   = "${local.name}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = local.aws_size_map[var.size].cpu
  memory                   = local.aws_size_map[var.size].memory
  task_role_arn            = var.task_role_arn != "" ? var.task_role_arn : null
  execution_role_arn       = var.execution_role_arn != "" ? var.execution_role_arn : null

  container_definitions = jsonencode([
    {
      name      = "script-runner"
      image     = var.image
      essential = true
      portMappings = [
        { containerPort = 2222, protocol = "tcp" }
      ]
      environment = [
        { name = "SSH_PUBLIC_KEY", value = var.ssh_public_key }
      ]
    }
  ])

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  tags = local.runner_tags
}

resource "aws_ecs_service" "script_runner" {
  count           = local.is_aws ? 1 : 0
  name            = local.name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.script_runner[0].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  tags = local.runner_tags
}

# --------------------------------------------------------------------------- #
# Azure: Container App.                                                        #
# --------------------------------------------------------------------------- #
resource "azurerm_container_app" "script_runner" {
  count                        = local.is_azure ? 1 : 0
  name                         = local.name
  container_app_environment_id = var.container_app_environment_id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  tags                         = local.runner_tags

  template {
    min_replicas = 1
    max_replicas = 1
    container {
      name   = "script-runner"
      image  = var.image
      cpu    = local.azure_size_map[var.size].cpu
      memory = local.azure_size_map[var.size].memory
      env {
        name        = "SSH_PUBLIC_KEY"
        secret_name = "ssh-public-key"
      }
    }
  }

  ingress {
    external_enabled = false
    target_port      = 2222
    transport        = "tcp"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  secret {
    name  = "ssh-public-key"
    value = var.ssh_public_key
  }
}

# --------------------------------------------------------------------------- #
# GCP: Cloud Run service.                                                      #
# --------------------------------------------------------------------------- #
resource "google_cloud_run_v2_service" "script_runner" {
  count    = local.is_gcp ? 1 : 0
  name     = local.name
  project  = var.project_id
  location = var.gcp_region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  labels   = local.runner_tags

  template {
    service_account = var.service_account_email != "" ? var.service_account_email : null
    containers {
      image = var.image
      ports {
        container_port = 2222
      }
      env {
        name  = "SSH_PUBLIC_KEY"
        value = var.ssh_public_key
      }
      resources {
        limits = {
          cpu    = local.gcp_size_map[var.size].cpu
          memory = local.gcp_size_map[var.size].memory
        }
      }
    }
  }
}
