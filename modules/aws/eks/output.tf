output "cluster_name" {
  value = aws_eks_cluster.eks_cluster.name
}

output "cluster_arn" {
  value = aws_eks_cluster.eks_cluster.arn
}

output "auth_config_command" {
  value = join(" ", ["aws eks update-kubeconfig --region", var.region, "--name", aws_eks_cluster.eks_cluster.name])
}

output "service_account_role_arn" {
  value = aws_iam_role.service_account_role.arn
}

output "kms_key_tags" {
  description = "Tags on the KMS key used for the EKS secret."
  value       = aws_kms_key.key.tags
}
