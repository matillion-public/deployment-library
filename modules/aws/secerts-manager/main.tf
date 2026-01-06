resource "aws_secretsmanager_secret" "agent_secret" {
  name        = "${var.name}-agent-secret"
}

resource "aws_secretsmanager_secret_version" "agent_secret_version" {
  secret_id     = aws_secretsmanager_secret.agent_secret.id
  secret_string = jsonencode({
      client_id     = var.client_id
      client_secret = var.client_secret
    })
  
}