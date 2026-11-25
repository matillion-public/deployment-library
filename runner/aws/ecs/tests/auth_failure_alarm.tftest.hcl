# Run with: terraform test  (from runner/aws/ecs)
#
# auth_failure_alarm_actions passed through the root to the ECS module. Uses a mock provider, so no AWS credentials or resources are needed.

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

run "no_auth_failure_alarm_by_default" {
  command = plan

  assert {
    condition     = module.runner.auth_failure_alarm_name == null
    error_message = "No alarm should be created when auth_failure_alarm_actions is empty."
  }
}

run "auth_failure_alarm_actions_reach_the_module" {
  command = plan

  variables {
    auth_failure_alarm_actions = ["arn:aws:sns:eu-west-1:123456789012:alerts"]
  }

  assert {
    condition     = module.runner.auth_failure_alarm_name == "t-abc123-runner-auth-failures"
    error_message = "auth_failure_alarm_actions must reach the ECS module and create the alarm."
  }
}
