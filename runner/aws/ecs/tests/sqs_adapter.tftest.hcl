# Run with: terraform test  (from runner/aws/ecs)
#
# SQS adapter naming, API URL and queue URL output as wired through the root. Uses a mock provider, so no AWS credentials or resources are needed.

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

run "queue_url_output_is_the_existing_queue_url" {
  command = plan

  variables {
    sqs_adapter_create_queue       = false
    sqs_adapter_existing_queue_arn = "arn:aws:sqs:eu-west-1:123456789012:existing.fifo"
    sqs_adapter_existing_queue_url = "https://sqs.eu-west-1.amazonaws.com/123456789012/existing.fifo"
  }

  assert {
    condition     = output.sqs_pipeline_trigger_queue_url == "https://sqs.eu-west-1.amazonaws.com/123456789012/existing.fifo"
    error_message = "sqs_pipeline_trigger_queue_url must be the adapter's source queue URL."
  }
}

run "queue_url_output_is_null_when_disabled" {
  command = plan

  variables {
    enable_sqs_pipeline_trigger = false
  }

  assert {
    condition     = output.sqs_pipeline_trigger_queue_url == null
    error_message = "sqs_pipeline_trigger_queue_url must be null when the SQS trigger is disabled."
  }
}

run "queue_url_output_is_the_created_queue_url" {
  command = plan

  override_resource {
    target          = module.sqs_dpc_adapter[0].aws_sqs_queue.source[0]
    override_during = plan
    values          = { url = "https://sqs.eu-west-1.amazonaws.com/123456789012/matillion-dpc-requests.fifo" }
  }

  assert {
    condition     = output.sqs_pipeline_trigger_queue_url == "https://sqs.eu-west-1.amazonaws.com/123456789012/matillion-dpc-requests.fifo"
    error_message = "sqs_pipeline_trigger_queue_url must be the URL of the queue the adapter creates."
  }
}

run "queue_url_output_is_null_for_an_existing_queue_without_a_url" {
  command = plan

  variables {
    sqs_adapter_create_queue       = false
    sqs_adapter_existing_queue_arn = "arn:aws:sqs:eu-west-1:123456789012:existing.fifo"
  }

  assert {
    condition     = output.sqs_pipeline_trigger_queue_url == null
    error_message = "sqs_pipeline_trigger_queue_url must be null, not empty, when no existing queue URL is given."
  }
}
