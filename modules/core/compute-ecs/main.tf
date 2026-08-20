# modules/core/compute-ecs  (AWS)
#
# Declares the agent compute service: agent_service = aws_ecs_service named
# "{deployment_name}-agent". Mirrors the production modules/aws/ecs module but
# kept thin so the composer path resolves. The service's task role is the
# agent_role from core/auth-iam (var.agent_role_arn), which makes the
# compute -> auth (FOUNDATION) dependency explicit and ordered.

locals {
  # Fargate-valid (cpu, memory) pairs.
  runner_size_map = {
    small  = { cpu = 1024, memory = 4096 }
    medium = { cpu = 2048, memory = 8192 }
    large  = { cpu = 4096, memory = 16384 }
    xlarge = { cpu = 8192, memory = 32768 }
  }
  cpu            = local.runner_size_map[var.runner_size].cpu
  memory         = local.runner_size_map[var.runner_size].memory
  service_name   = "${var.deployment_name}-agent"
  execution_role = var.execution_role_arn != "" ? var.execution_role_arn : var.agent_role_arn
}

resource "aws_ecs_cluster" "agent" {
  name = "${var.deployment_name}-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  tags = var.tags
}

resource "aws_cloudwatch_log_group" "agent" {
  name              = "/ecs/${local.service_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn != "" ? var.log_kms_key_arn : null
  tags              = var.tags
}

resource "aws_ecs_task_definition" "agent" {
  # checkov:skip=CKV_AWS_249:execution_role_arn defaults to the agent role for a minimal single-role deployment; pass a distinct execution_role_arn to separate them in production.
  family                   = "${local.service_name}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = local.cpu
  memory                   = local.memory
  task_role_arn            = var.agent_role_arn
  execution_role_arn       = local.execution_role

  container_definitions = jsonencode([
    {
      name                   = "agent"
      image                  = var.image_url
      essential              = true
      readonlyRootFilesystem = true
      environment = [
        { name = "MATILLION_ACCOUNT_ID", value = var.account_id },
        { name = "MATILLION_AGENT_ID", value = var.agent_id },
        { name = "MATILLION_REGION", value = var.matillion_region },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.agent.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "agent"
        }
      }
    }
  ])

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  tags = var.tags
}

resource "aws_ecs_service" "agent_service" {
  name            = local.service_name
  cluster         = aws_ecs_cluster.agent.id
  task_definition = aws_ecs_task_definition.agent.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Least-privilege deploy-time permission set (mirrors the composer contract).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "deployer" {
  statement {
    sid    = "EcsServiceLifecycle"
    effect = "Allow"
    actions = [
      "ecs:CreateService",
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]
    resources = ["arn:aws:ecs:${var.region}:*:service/${var.deployment_name}-cluster/*"]
  }
  statement {
    sid    = "NetworkDiscovery"
    effect = "Allow"
    actions = [
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
    ]
    # Describe* actions do not support resource-level permissions.
    resources = ["*"]
  }
  statement {
    sid       = "CreateLogGroup"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup"]
    resources = ["arn:aws:logs:${var.region}:*:log-group:/ecs/${local.service_name}*"]
  }
}

resource "aws_iam_policy" "deployer" {
  count       = var.create_deployer_policy ? 1 : 0
  name        = "${var.deployment_name}-compute-ecs-deployer"
  description = "Least-privilege permissions to provision the core/compute-ecs module."
  policy      = data.aws_iam_policy_document.deployer.json
  tags        = var.tags
}
