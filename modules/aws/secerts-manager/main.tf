resource "aws_secretsmanager_secret" "runner_secret" {
  name = var.secret_name
}

resource "aws_secretsmanager_secret_version" "runner_secret_version" {
  secret_id = aws_secretsmanager_secret.runner_secret.id
  secret_string = jsonencode({
    client_id     = var.client_id
    client_secret = var.client_secret
  })

}
