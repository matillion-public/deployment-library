resource "aws_iam_role" "ecs_task_role" {
  name               = join("-", [var.name, "matillion-ecs-task-role"])
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = {
        Service = ["ecs-tasks.amazonaws.com", "ec2.amazonaws.com"]
      }
      Action    = ["sts:AssumeRole"]
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
  name   = "matillion_etl_agent_role"
  role   = aws_iam_role.ecs_task_role.id
  policy = file("${path.module}/templates/ecs_task_role_policy.json")
}

resource "aws_iam_instance_profile" "ecs_task_role_instance_profile" {
  name  = join("-", [var.name, "matillion-ecs-task-instance-profile"])
  path  = "/"
  role = aws_iam_role.ecs_task_role.name
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = join("-", [var.name, "task-execution-role"])
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = {
        Service = ["ecs-tasks.amazonaws.com"]
      }
      Action    = ["sts:AssumeRole"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_role_policy" {
  name = "GetETLAgentSecretValue"
  role = aws_iam_role.ecs_task_execution_role.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [var.agent_secret_arn]
      }
    ]
  })
}
