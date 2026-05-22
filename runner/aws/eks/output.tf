output "cluster_name" {
  value = module.eks.cluster_name
}
output "cluster_subnet_ids" {
  value = module.deployment.all_subnet_ids
}

output "public_subnet_ids" {
  value = module.deployment.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.deployment.private_subnet_ids
}
output "eks_cluster" {
  value = module.eks.cluster_name

}
output "auth_config_command" {
  value = module.eks.auth_config_command

}

output "eks_cluster_arn" {
  value = module.eks.cluster_arn

}

output "service_account_role_arn" {
  value = module.eks.service_account_role_arn
}