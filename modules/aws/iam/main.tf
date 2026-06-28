locals {
  script_runner_policy_statements = var.script_runner_extension_library_bucket_arn != "" ? [
    {
      Sid    = "ExtensionLibraryS3"
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        var.script_runner_extension_library_bucket_arn,
        "${var.script_runner_extension_library_bucket_arn}/*"
      ]
    }
  ] : []
}

resource "aws_iam_role" "ecs_task_role" {
  name = join("-", [var.name, "matillion-ecs-task-role"])
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["ecs-tasks.amazonaws.com", "ec2.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_role_secrets_manager" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

resource "aws_iam_role_policy_attachment" "ecs_task_role_cloudwatch" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

resource "aws_iam_role_policy" "ecs_task_role_policy" {
  name   = "matillion_etl_runner_role"
  role   = aws_iam_role.ecs_task_role.id
  policy = file("${path.module}/templates/ecs_task_role_policy.json")
}

resource "aws_iam_instance_profile" "ecs_task_role_instance_profile" {
  name = join("-", [var.name, "matillion-ecs-task-instance-profile"])
  path = "/"
  role = aws_iam_role.ecs_task_role.name
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = join("-", [var.name, "task-execution-role"])
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["ecs-tasks.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_role_policy" {
  name = "GetETLRunnerSecretValue"
  role = aws_iam_role.ecs_task_execution_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [var.runner_secret_arn]
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_task_execution_role_keypair_policy" {
  count = var.enable_script_runner ? 1 : 0

  name = "GetScriptRunnerKeypairSecretValue"
  role = aws_iam_role.ecs_task_execution_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [var.runner_keypair_secret_arn]
      }
    ]
  })

  lifecycle {
    precondition {
      condition     = var.runner_keypair_secret_arn != ""
      error_message = "runner_keypair_secret_arn must be set when enable_script_runner is true."
    }
  }
}

# ── Script runner task role (narrow policy) ────────────────────────────────────

resource "aws_iam_role" "script_runner_task_role" {
  count = var.enable_script_runner ? 1 : 0

  name = join("-", [var.name, "script-runner-task-role"])
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["ecs-tasks.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}

# No policy is attached when script_runner_extension_library_bucket_arn is unset — the script runner
# accesses its container image and secret via the execution role; the task role needs no AWS permissions
# unless extension library S3 access is required.
resource "aws_iam_role_policy" "script_runner_task_role_policy" {
  count = var.enable_script_runner && var.script_runner_extension_library_bucket_arn != "" ? 1 : 0

  name = "ScriptRunnerExtensionLibraryS3Access"
  role = aws_iam_role.script_runner_task_role[0].id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.script_runner_policy_statements
  })
}
