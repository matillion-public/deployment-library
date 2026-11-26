# Run with: terraform test  (from modules/aws/lambda/sqs-dpc-adapter)
#
# lambda_policy_arn replaces the adapter role's inline policy with an attachment
# of the supplied policy. Uses a mock provider, so no AWS credentials or
# resources are needed.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_data "aws_secretsmanager_secret" {
    defaults = { arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:dpc-abcdef" }
  }
}

variables {
  aws_region  = "eu-west-1"
  image_uri   = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/maia-queue-adapter:current"
  secret_name = "dpc"
}

run "default_creates_inline_policy" {
  command = plan

  assert {
    condition     = length(aws_iam_role_policy.lambda) == 1
    error_message = "The adapter inline policy must be created by default."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.lambda_supplied) == 0
    error_message = "No supplied policy attachment may be created by default."
  }
}

run "lambda_policy_arn_replaces_inline_policy" {
  command = plan

  variables {
    lambda_policy_arn = "arn:aws:iam::123456789012:policy/cmtest-sqs-adapter"
  }

  assert {
    condition     = length(aws_iam_role_policy.lambda) == 0
    error_message = "The adapter inline policy must not be created when lambda_policy_arn is set."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.lambda_supplied) == 1 && aws_iam_role_policy_attachment.lambda_supplied[0].policy_arn == "arn:aws:iam::123456789012:policy/cmtest-sqs-adapter"
    error_message = "lambda_policy_arn must be attached to the adapter role."
  }
}

run "invalid_lambda_policy_arn_fails" {
  command = plan

  variables {
    lambda_policy_arn = "not-an-arn"
  }

  expect_failures = [var.lambda_policy_arn]
}
