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

# Stores the SSH public key(s) authorised to connect to the script runner.
# The script runner reads authorized_keys from this secret at startup via RUNNER_AUTHORIZED_KEYS.
resource "aws_secretsmanager_secret" "runner_keypair_secret" {
  count = var.enable_keypair_secret ? 1 : 0
  name  = var.runner_keypair_secret_name
}

resource "aws_secretsmanager_secret_version" "runner_keypair_secret_version" {
  count     = var.enable_keypair_secret ? 1 : 0
  secret_id = aws_secretsmanager_secret.runner_keypair_secret[0].id
  secret_string = jsonencode({
    authorized_keys = var.runner_authorized_keys
  })

  lifecycle {
    precondition {
      condition     = var.runner_authorized_keys != ""
      error_message = "runner_authorized_keys must be set when enable_keypair_secret is true."
    }
  }
}
