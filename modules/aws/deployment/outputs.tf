output "public_subnet_ids" {
  value = aws_subnet.public_subnet[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private_subnet[*].id
}

output "all_subnet_ids" {
  value = concat(aws_subnet.public_subnet[*].id, aws_subnet.private_subnet[*].id)
}

output "k8s_security_group_id" {
  value = aws_security_group.k8s_security_group.id
}
