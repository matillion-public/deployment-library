# Security group rules for agent access
# These rules allow the Lambda (or external access) to reach ECS agents on actuator ports

# Data source to get information about the provided security group
data "aws_security_group" "agent_sg" {
  count = var.vpc_config != null && length(try(var.vpc_config.security_group_ids, [])) > 0 ? 1 : 0
  id    = var.vpc_config.security_group_ids[0]
}

# For agents with public IPs (Lambda outside VPC scenario)
resource "aws_security_group_rule" "allow_internet_to_actuator" {
  count = var.create_internet_access_rules && var.vpc_config != null && length(try(var.vpc_config.security_group_ids, [])) > 0 ? length(var.vpc_config.security_group_ids) : 0
  
  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  security_group_id = var.vpc_config.security_group_ids[count.index]
  cidr_blocks       = ["0.0.0.0/0"]  # Allow from internet (for public agents)
  description       = "Allow Lambda (outside VPC) to access agent actuator endpoints"
}

resource "aws_security_group_rule" "allow_internet_to_metrics_exporter" {
  count = var.create_internet_access_rules && var.vpc_config != null && length(try(var.vpc_config.security_group_ids, [])) > 0 ? length(var.vpc_config.security_group_ids) : 0
  
  type              = "ingress"
  from_port         = 8000
  to_port           = 8000
  protocol          = "tcp"
  security_group_id = var.vpc_config.security_group_ids[count.index]
  cidr_blocks       = ["0.0.0.0/0"]  # Allow from internet (for public agents)
  description       = "Allow Lambda (outside VPC) to access custom metrics exporter"
}

# For agents with private IPs only (Lambda in VPC scenario)
resource "aws_security_group_rule" "allow_vpc_to_actuator" {
  count = var.vpc_config != null && length(try(var.vpc_config.security_group_ids, [])) > 0 ? length(var.vpc_config.security_group_ids) : 0
  
  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  security_group_id = var.vpc_config.security_group_ids[count.index]
  source_security_group_id = length(aws_security_group.lambda_sg) > 0 ? aws_security_group.lambda_sg[0].id : var.vpc_config.security_group_ids[0]
  description       = "Allow Lambda (in VPC) to access agent actuator endpoints"
}

resource "aws_security_group_rule" "allow_vpc_to_metrics_exporter" {
  count = var.vpc_config != null && length(try(var.vpc_config.security_group_ids, [])) > 0 ? length(var.vpc_config.security_group_ids) : 0
  
  type              = "ingress"
  from_port         = 8000
  to_port           = 8000
  protocol          = "tcp"
  security_group_id = var.vpc_config.security_group_ids[count.index]
  source_security_group_id = length(aws_security_group.lambda_sg) > 0 ? aws_security_group.lambda_sg[0].id : var.vpc_config.security_group_ids[0]
  description       = "Allow Lambda (in VPC) to access custom metrics exporter"
}