# Optional security group for Lambda function
# Only created if VPC config is provided but no security groups specified

resource "aws_security_group" "lambda_sg" {
  count       = var.vpc_config != null && length(try(var.vpc_config.security_group_ids, [])) == 0 ? 1 : 0
  name        = "${var.name}-saturation-monitor-lambda-sg"
  description = "Security group for ECS Agent Saturation Monitor Lambda"
  vpc_id      = var.vpc_config.vpc_id

  # Outbound access to ECS tasks on actuator port
  egress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
    description = "Access to ECS task actuator endpoints"
  }

  # Outbound access to custom metrics exporter port
  egress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
    description = "Access to custom metrics exporter"
  }

  # HTTPS access for AWS APIs (needed if no VPC endpoints)
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS access for AWS APIs and VPC endpoints"
  }

  tags = {
    Name = "${var.name}-saturation-monitor-lambda-sg"
  }
}


# Output the security group ID if created
output "lambda_security_group_id" {
  description = "Security group ID for Lambda function (if created)"
  value       = length(aws_security_group.lambda_sg) > 0 ? aws_security_group.lambda_sg[0].id : null
}