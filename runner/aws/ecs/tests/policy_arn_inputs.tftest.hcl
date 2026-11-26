# Run with: terraform test  (from runner/aws/ecs)
#
# The *_policy_arn inputs plan on a fresh deployment and reject values that are
# not IAM policy ARNs. random_string.salt is not overridden, so it stays unknown
# at plan as it is before the first apply. Uses a mock provider, so no AWS
# credentials or resources are needed.

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
  mock_data "aws_subnets" {
    defaults = { ids = [] }
  }
}

variables {
  name                        = "t"
  region                      = "eu-west-1"
  account_id                  = "00000000-0000-0000-0000-000000000000"
  agent_id                    = "00000000-0000-0000-0000-000000000001"
  image_url                   = "example.com/runner:latest"
  client_id                   = "id"
  client_secret               = "secret"
  use_existing_vpc            = true
  vpc_id                      = "vpc-123"
  use_existing_subnet         = true
  subnet_ids                  = ["subnet-1"]
  use_existing_security_group = true
  security_group_ids          = ["sg-1"]
}

run "every_input_set_plans_on_a_fresh_deployment" {
  command = plan

  variables {
    enable_script_runner                       = true
    runner_authorized_keys                     = "ssh-ed25519 AAAA test"
    script_runner_extension_library_bucket_arn = "arn:aws:s3:::ext-lib"
    enable_sqs_pipeline_trigger                = true
    sqs_adapter_image_uri                      = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/maia-queue-adapter:current"
    ecs_task_role_policy_arn                   = "arn:aws:iam::123456789012:policy/cmtest-task"
    ecs_task_execution_role_policy_arn         = "arn:aws:iam::123456789012:policy/cmtest-exec-secret"
    ecs_task_execution_role_keypair_policy_arn = "arn:aws:iam::123456789012:policy/cmtest-exec-keypair"
    script_runner_extension_library_policy_arn = "arn:aws:iam::123456789012:policy/cmtest-extlib"
    sqs_adapter_lambda_policy_arn              = "arn:aws:iam::123456789012:policy/cmtest-sqs-adapter"
  }
}

run "invalid_root_policy_arns_fail" {
  command = plan

  variables {
    ecs_task_role_policy_arn                   = "not-an-arn"
    ecs_task_execution_role_policy_arn         = "not-an-arn"
    ecs_task_execution_role_keypair_policy_arn = "not-an-arn"
    script_runner_extension_library_policy_arn = "not-an-arn"
    sqs_adapter_lambda_policy_arn              = "not-an-arn"
  }

  expect_failures = [
    var.ecs_task_role_policy_arn,
    var.ecs_task_execution_role_policy_arn,
    var.ecs_task_execution_role_keypair_policy_arn,
    var.script_runner_extension_library_policy_arn,
    var.sqs_adapter_lambda_policy_arn,
  ]
}
