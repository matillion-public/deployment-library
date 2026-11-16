# Run with: terraform test  (from modules/aws/secerts-manager)
#
# Secret naming, tags and recovery window. Uses a mock provider, so no AWS credentials or resources are needed.

mock_provider "aws" {}

variables {
  name          = "my-runner-abc123"
  client_id     = "id"
  client_secret = "secret"
}

run "name_defaults_to_deployment_prefix" {
  command = plan

  assert {
    condition     = aws_secretsmanager_secret.runner_secret.name == "my-runner-abc123-oauth-credentials"
    error_message = "Default secret name must be prefixed with the deployment name, got ${aws_secretsmanager_secret.runner_secret.name}."
  }
}

run "name_override_is_used" {
  command = plan

  variables {
    secret_name = "custom-oauth"
  }

  assert {
    condition     = aws_secretsmanager_secret.runner_secret.name == "custom-oauth"
    error_message = "secret_name override must be used verbatim, got ${aws_secretsmanager_secret.runner_secret.name}."
  }
}

run "tags_are_applied" {
  command = plan

  variables {
    tags = { Owner = "team" }
  }

  assert {
    condition     = aws_secretsmanager_secret.runner_secret.tags["Owner"] == "team" && aws_secretsmanager_secret.runner_secret.tags["Name"] == "my-runner-abc123-oauth-credentials"
    error_message = "Secret must carry var.tags and a Name tag."
  }
}

run "recovery_window_defaults_to_immediate_deletion" {
  command = plan

  assert {
    condition     = aws_secretsmanager_secret.runner_secret.recovery_window_in_days == 0
    error_message = "Secret must default to recovery_window_in_days = 0."
  }
}

run "keypair_name_defaults_to_deployment_prefix" {
  command = plan

  variables {
    enable_keypair_secret  = true
    runner_authorized_keys = "ssh-ed25519 AAAA"
  }

  assert {
    condition     = aws_secretsmanager_secret.runner_keypair_secret[0].name == "my-runner-abc123-runner-keypair" && aws_secretsmanager_secret.runner_keypair_secret[0].recovery_window_in_days == 0
    error_message = "Keypair secret must default to the deployment-prefixed name with recovery_window_in_days = 0."
  }
}

run "keypair_name_override_is_used" {
  command = plan

  variables {
    enable_keypair_secret      = true
    runner_authorized_keys     = "ssh-ed25519 AAAA"
    runner_keypair_secret_name = "custom-keypair"
  }

  assert {
    condition     = aws_secretsmanager_secret.runner_keypair_secret[0].name == "custom-keypair"
    error_message = "runner_keypair_secret_name override must be used verbatim."
  }
}
