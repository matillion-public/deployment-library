# VPC Endpoints for Lambda to access AWS services from within VPC
# This allows the Lambda to reach AWS APIs without internet gateway
# Note: If you have existing VPC endpoints, set create_vpc_endpoints = false to avoid conflicts


# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  count       = var.vpc_config != null && var.create_vpc_endpoints ? 1 : 0
  name        = "${var.name}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = var.vpc_config.vpc_id

  # Allow HTTPS traffic from Lambda security group
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = length(aws_security_group.lambda_sg) > 0 ? [aws_security_group.lambda_sg[0].id] : var.vpc_config.security_group_ids
    description     = "HTTPS access from Lambda to VPC endpoints"
  }

  # Allow all outbound traffic (default)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name = "${var.name}-vpc-endpoints-sg"
  }
}

# ECS VPC Endpoint
resource "aws_vpc_endpoint" "ecs" {
  count = var.vpc_config != null && var.create_vpc_endpoints ? 1 : 0
  
  vpc_id              = var.vpc_config.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.vpc_config.subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = var.vpc_endpoint_private_dns_enabled
  
  lifecycle {
    ignore_changes = [private_dns_enabled]
  }
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "ecs:ListClusters",
          "ecs:ListServices", 
          "ecs:DescribeServices",
          "ecs:ListTasks",
          "ecs:DescribeTasks",
          "ecs:DescribeTaskDefinition"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.name}-ecs-endpoint"
  }
}

# CloudWatch VPC Endpoint
resource "aws_vpc_endpoint" "cloudwatch" {
  count = var.vpc_config != null && var.create_vpc_endpoints ? 1 : 0
  
  vpc_id              = var.vpc_config.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.monitoring"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.vpc_config.subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = var.vpc_endpoint_private_dns_enabled
  
  lifecycle {
    ignore_changes = [private_dns_enabled]
  }
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.name}-cloudwatch-endpoint"
  }
}

# CloudWatch Logs VPC Endpoint (for Lambda logging)
resource "aws_vpc_endpoint" "logs" {
  count = var.vpc_config != null && var.create_vpc_endpoints ? 1 : 0
  
  vpc_id              = var.vpc_config.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.vpc_config.subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = var.vpc_endpoint_private_dns_enabled

  lifecycle {
    ignore_changes = [private_dns_enabled]
  }

  tags = {
    Name = "${var.name}-logs-endpoint"
  }
}

# Note: Interface VPC endpoints automatically handle DNS resolution
# No route table associations are needed for Interface endpoints
# They create ENIs in the specified subnets and handle traffic automatically