output "ECSCluster" {
  value = module.runner.ECSCluster
}

output "RunnerSecret" {
  value = module.runner.RunnerSecret
}

output "ECSService" {
  value = module.runner.ECSService
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = data.aws_vpc.vpc.id
}

output "subnet_ids" {
  description = "The IDs of the subnets"
  value       = var.use_existing_subnet ? var.subnet_ids : aws_subnet.ecs_subnet[*].id
}

output "security_group_id" {
  description = "The ID of the security group"
  value       = var.use_existing_security_group ? var.security_group_ids : [aws_security_group.ecs_security_group[0].id]
}
