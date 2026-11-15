# Run with: terraform test  (from runner/aws/ecs)
#
# Secret naming, tags and recovery window as wired through the root. Uses a mock provider, so no AWS credentials or resources are needed.

mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = { cidr_block = "10.0.0.0/16" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["eu-west-1a", "eu-west-1b", "eu-west-1c"] }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

override_resource {
  target          = random_string.salt
  override_during = plan
  values          = { result = "abc123" }
}

variables {
  name          = "t"
  region        = "eu-west-1"
  account_id    = "00000000-0000-0000-0000-000000000000"
  agent_id      = "00000000-0000-0000-0000-000000000001"
  image_url     = "example.com/runner:latest"
  client_id     = "id"
  client_secret = "secret"
}

run "oauth_secret_name_defaults_to_deployment_prefix" {
  command = plan

  assert {
    condition     = module.secert_manager.runner_secret_name == "t-abc123-oauth-credentials"
    error_message = "Default OAuth secret name must be <name>-<salt>-oauth-credentials."
  }
}

run "oauth_secret_name_override_is_used" {
  command = plan

  variables {
    secret_name = "custom-oauth"
  }

  assert {
    condition     = module.secert_manager.runner_secret_name == "custom-oauth"
    error_message = "secret_name override must be used verbatim."
  }
}

run "tags_reach_oauth_secret" {
  command = plan

  variables {
    tags = { Owner = "team" }
  }

  assert {
    condition     = module.secert_manager.runner_secret_tags["Owner"] == "team"
    error_message = "var.tags must reach the OAuth secret."
  }
}

run "keypair_secret_name_defaults_to_deployment_prefix" {
  command = plan

  variables {
    enable_script_runner    = true
    script_runner_image_url = "example.com/script-runner:latest"
    runner_authorized_keys  = "ssh-ed25519 AAAA"
  }

  assert {
    condition     = module.secert_manager.runner_keypair_secret_name == "t-abc123-runner-keypair"
    error_message = "Default keypair secret name must be <name>-<salt>-runner-keypair."
  }
}
