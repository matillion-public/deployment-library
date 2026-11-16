# Run with: terraform test  (from runner/aws/ecs)
#
# SQS adapter naming and API URL as wired through the root. Uses a mock provider, so no AWS credentials or resources are needed.

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
  name                        = "t"
  region                      = "eu-west-1"
  account_id                  = "00000000-0000-0000-0000-000000000000"
  agent_id                    = "00000000-0000-0000-0000-000000000001"
  image_url                   = "example.com/runner:latest"
  client_id                   = "id"
  client_secret               = "secret"
  enable_sqs_pipeline_trigger = true
  sqs_adapter_image_uri       = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/maia-queue-adapter:current"
}

run "adapter_lambda_name_includes_the_deployment_salt" {
  command = plan

  assert {
    condition     = module.sqs_dpc_adapter[0].lambda_function_name == "t-abc123-maia-sqs-adapter"
    error_message = "The adapter function name must include the deployment salt."
  }
}

run "api_url_follows_matillion_region" {
  command = plan

  variables {
    matillion_region = "us1"
  }

  assert {
    condition     = local.sqs_adapter_matillion_api_url == "https://us1.api.matillion.com/dpc/v1"
    error_message = "The adapter API URL must follow matillion_region."
  }
}

run "explicit_api_url_wins" {
  command = plan

  variables {
    matillion_region              = "us1"
    sqs_adapter_matillion_api_url = "https://example.test/dpc/v1"
  }

  assert {
    condition     = local.sqs_adapter_matillion_api_url == "https://example.test/dpc/v1"
    error_message = "An explicit sqs_adapter_matillion_api_url must be used as given."
  }
}
