# Run with: terraform test  (from runner/aws/eks)
#
# SQS adapter outputs as wired through the root. Uses a mock provider, so no AWS credentials or
# resources are needed.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["eu-west-1a", "eu-west-1b"] }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

variables {
  name                        = "t"
  region                      = "eu-west-1"
  tags                        = {}
  enable_sqs_pipeline_trigger = true
  sqs_adapter_image_uri       = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/maia-queue-adapter:current"
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
