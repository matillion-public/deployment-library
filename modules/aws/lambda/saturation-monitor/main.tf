# Lambda function for ECS Agent Saturation Monitoring

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Create deployment package (no external dependencies needed)
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}"
  output_path = "${path.module}/lambda_deployment.zip"
  excludes    = ["main.tf", "variables.tf", "outputs.tf", "lambda_deployment.zip", ".gitignore", "requirements.txt", "main_with_layer.tf.alternative"]
  
  # Force rebuild when source code changes
  depends_on = [
    local_file.lambda_function_py
  ]
}

# Track the lambda function file to trigger rebuilds
resource "local_file" "lambda_function_py" {
  content  = file("${path.module}/lambda_function.py")
  filename = "${path.module}/.lambda_function_py.tmp"
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${var.name}-saturation-monitor-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.name}-saturation-monitor-lambda-role"
  }
}

# IAM policy for Lambda function
resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.name}-saturation-monitor-lambda-policy"
  description = "Policy for ECS Agent Saturation Monitor Lambda"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.name}-saturation-monitor*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:ListClusters",
          "ecs:ListServices",
          "ecs:DescribeServices",
          "ecs:ListTasks",
          "ecs:DescribeTasks",
          "ecs:DescribeTaskDefinition"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeNetworkInterfaces",
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeNetworkInterfaceAttribute",
          "ec2:DetachNetworkInterface"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.name}-saturation-monitor"
  retention_in_days = 14

  tags = {
    Name = "${var.name}-saturation-monitor-logs"
  }
}

# Lambda function
resource "aws_lambda_function" "saturation_monitor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.name}-saturation-monitor"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.11"
  timeout         = 300  # 5 minutes
  memory_size     = 256

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      CLOUDWATCH_NAMESPACE      = var.cloudwatch_namespace
      LOG_LEVEL                = var.log_level
      AGENT_SERVICE_INDICATORS = var.agent_service_indicators
      DEPLOYMENT_MODE          = var.deployment_mode
    }
  }

  # VPC configuration for accessing ECS tasks
  dynamic "vpc_config" {
    for_each = var.vpc_config != null ? [var.vpc_config] : []
    content {
      subnet_ids = vpc_config.value.subnet_ids
      security_group_ids = length(try(vpc_config.value.security_group_ids, [])) > 0 ? vpc_config.value.security_group_ids : [aws_security_group.lambda_sg[0].id]
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_policy_attachment,
    aws_cloudwatch_log_group.lambda_logs,
  ]

  tags = {
    Name = "${var.name}-saturation-monitor"
  }
}

# EventBridge rule to trigger Lambda
resource "aws_cloudwatch_event_rule" "saturation_monitor_schedule" {
  name                = "${var.name}-saturation-monitor-schedule"
  description         = "Trigger ECS Agent Saturation Monitor Lambda"
  schedule_expression = var.schedule_expression

  tags = {
    Name = "${var.name}-saturation-monitor-schedule"
  }
}

# EventBridge target
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.saturation_monitor_schedule.name
  target_id = "SaturationMonitorLambdaTarget"
  arn       = aws_lambda_function.saturation_monitor.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.saturation_monitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.saturation_monitor_schedule.arn
}

# CloudWatch Dashboard for monitoring the Lambda and metrics
resource "aws_cloudwatch_dashboard" "saturation_monitor_dashboard" {
  count          = var.create_dashboard ? 1 : 0
  dashboard_name = "${var.name}-agent-saturation"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["ECS/AgentSaturation", "ActiveTaskCount"],
            [".", "ActiveRequestCount"],
            [".", "OpenSessionsCount"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "ECS Agent Saturation Metrics (Per Task)"
          period  = 60
          stat    = "Maximum"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.saturation_monitor.function_name],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Lambda Function Metrics"
          period  = 300
          stat    = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["ECS/AgentSaturation", "ActiveTaskCount"],
            [".", "ActiveRequestCount"],
            [".", "OpenSessionsCount"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "All Agent Saturation Metrics (By Task)"
          period  = 60
          stat    = "Maximum"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["ECS/AgentSaturation", "AgentStatus"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "All Agent Health Status (By Task)"
          period  = 60
          stat    = "Maximum"
        }
      }
    ]
  })
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "high_task_saturation" {
  count               = var.create_alarms ? 1 : 0
  alarm_name          = "${var.name}-high-task-saturation"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ActiveTaskCount"
  namespace           = var.cloudwatch_namespace
  period              = "300"
  statistic           = "Average"
  threshold           = var.high_task_count_threshold
  alarm_description   = "This metric monitors high task saturation across ECS agents"
  alarm_actions       = var.alarm_actions

  tags = {
    Name = "${var.name}-high-task-saturation"
  }
}

resource "aws_cloudwatch_metric_alarm" "high_request_queue" {
  count               = var.create_alarms ? 1 : 0
  alarm_name          = "${var.name}-high-request-queue"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ActiveRequestCount"
  namespace           = var.cloudwatch_namespace
  period              = "300"
  statistic           = "Average"
  threshold           = var.high_request_count_threshold
  alarm_description   = "This metric monitors high request queue buildup across ECS agents"
  alarm_actions       = var.alarm_actions

  tags = {
    Name = "${var.name}-high-request-queue"
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count               = var.create_alarms ? 1 : 0
  alarm_name          = "${var.name}-saturation-monitor-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors errors in the saturation monitor Lambda function"
  alarm_actions       = var.alarm_actions

  dimensions = {
    FunctionName = aws_lambda_function.saturation_monitor.function_name
  }

  tags = {
    Name = "${var.name}-saturation-monitor-errors"
  }
}