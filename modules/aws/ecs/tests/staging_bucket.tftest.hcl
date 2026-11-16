# Run with: terraform test  (from modules/aws/ecs)
#
# The staging bucket and its policy are always created, with the lower-cased
# deployment name.
# Uses a mock provider, so no AWS credentials or resources are needed.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_resource "aws_security_group" {
    defaults = { id = "sg-0runner0000000000" }
  }
}

variables {
  name                           = "Mixed-AbC123"
  region                         = "eu-west-1"
  account_id                     = "00000000-0000-0000-0000-000000000000"
  agent_id                       = "00000000-0000-0000-0000-000000000001"
  vpc_id                         = "vpc-0000000000000000"
  subnet_ids                     = ["subnet-00000000000000001"]
  security_group_ids             = []
  runner_task_role_execution_arn = "arn:aws:iam::123456789012:role/exec"
  runner_task_role_arn           = "arn:aws:iam::123456789012:role/task"
  runner_secret_arn              = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:runner"
}

run "staging_bucket_is_always_created" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket.staging_bucket) == 1 && length(aws_s3_bucket_policy.staging_bucket_policy) == 1
    error_message = "The staging bucket and its policy must always be created."
  }

  assert {
    condition     = aws_s3_bucket.staging_bucket[0].bucket == "mixed-abc123-stagging-bucket"
    error_message = "The staging bucket name must be the lower-cased deployment name."
  }
}
