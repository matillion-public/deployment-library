# Run with: terraform test  (from modules/aws/iam)
#
# Each *_policy_arn input replaces one inline role policy with an attachment of
# the supplied policy. Uses a mock provider, so no AWS credentials or resources
# are needed.

mock_provider "aws" {}

variables {
  name                                       = "t"
  runner_secret_arn                          = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:runner"
  enable_script_runner                       = true
  runner_keypair_secret_arn                  = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:keypair"
  script_runner_extension_library_bucket_arn = "arn:aws:s3:::ext-lib"
}

run "defaults_create_inline_policies" {
  command = plan

  assert {
    condition     = length(aws_iam_role_policy.ecs_task_role_policy) == 1
    error_message = "The task role inline policy must be created by default."
  }

  assert {
    condition     = length(aws_iam_role_policy.ecs_task_execution_role_policy) == 1
    error_message = "The execution role secret inline policy must be created by default."
  }

  assert {
    condition     = length(aws_iam_role_policy.ecs_task_execution_role_keypair_policy) == 1
    error_message = "The execution role keypair inline policy must be created by default."
  }

  assert {
    condition     = length(aws_iam_role_policy.script_runner_task_role_policy) == 1
    error_message = "The script runner extension library inline policy must be created by default."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.ecs_task_role_policy_supplied) == 0
    error_message = "No task role policy attachment may be created by default."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.ecs_task_execution_secret_policy_supplied) == 0
    error_message = "No execution role secret policy attachment may be created by default."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.ecs_task_execution_keypair_policy_supplied) == 0
    error_message = "No execution role keypair policy attachment may be created by default."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.script_runner_extension_library_policy_supplied) == 0
    error_message = "No script runner extension library policy attachment may be created by default."
  }
}

run "every_input_set_creates_no_inline_policy" {
  command = plan

  variables {
    ecs_task_role_policy_arn                   = "arn:aws:iam::123456789012:policy/cmtest-task"
    ecs_task_execution_role_policy_arn         = "arn:aws:iam::123456789012:policy/cmtest-exec-secret"
    ecs_task_execution_role_keypair_policy_arn = "arn:aws:iam::123456789012:policy/cmtest-exec-keypair"
    script_runner_extension_library_policy_arn = "arn:aws:iam::123456789012:policy/cmtest-extlib"
  }

  assert {
    condition     = length(aws_iam_role_policy.ecs_task_role_policy) == 0
    error_message = "The task role inline policy must not be created when ecs_task_role_policy_arn is set."
  }

  assert {
    condition     = length(aws_iam_role_policy.ecs_task_execution_role_policy) == 0
    error_message = "The execution role secret inline policy must not be created when ecs_task_execution_role_policy_arn is set."
  }

  assert {
    condition     = length(aws_iam_role_policy.ecs_task_execution_role_keypair_policy) == 0
    error_message = "The execution role keypair inline policy must not be created when ecs_task_execution_role_keypair_policy_arn is set."
  }

  assert {
    condition     = length(aws_iam_role_policy.script_runner_task_role_policy) == 0
    error_message = "The script runner extension library inline policy must not be created when script_runner_extension_library_policy_arn is set."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.ecs_task_role_policy_supplied) == 1 && aws_iam_role_policy_attachment.ecs_task_role_policy_supplied[0].policy_arn == "arn:aws:iam::123456789012:policy/cmtest-task"
    error_message = "ecs_task_role_policy_arn must be attached to the task role."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.ecs_task_execution_secret_policy_supplied) == 1 && aws_iam_role_policy_attachment.ecs_task_execution_secret_policy_supplied[0].policy_arn == "arn:aws:iam::123456789012:policy/cmtest-exec-secret"
    error_message = "ecs_task_execution_role_policy_arn must be attached to the execution role."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.ecs_task_execution_keypair_policy_supplied) == 1 && aws_iam_role_policy_attachment.ecs_task_execution_keypair_policy_supplied[0].policy_arn == "arn:aws:iam::123456789012:policy/cmtest-exec-keypair"
    error_message = "ecs_task_execution_role_keypair_policy_arn must be attached to the execution role."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.script_runner_extension_library_policy_supplied) == 1 && aws_iam_role_policy_attachment.script_runner_extension_library_policy_supplied[0].policy_arn == "arn:aws:iam::123456789012:policy/cmtest-extlib"
    error_message = "script_runner_extension_library_policy_arn must be attached to the script runner task role."
  }
}

run "script_runner_inputs_ignored_when_script_runner_disabled" {
  command = plan

  variables {
    enable_script_runner                       = false
    ecs_task_execution_role_keypair_policy_arn = "arn:aws:iam::123456789012:policy/cmtest-exec-keypair"
    script_runner_extension_library_policy_arn = "arn:aws:iam::123456789012:policy/cmtest-extlib"
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.ecs_task_execution_keypair_policy_supplied) == 0
    error_message = "The keypair policy must not be attached when enable_script_runner is false."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.script_runner_extension_library_policy_supplied) == 0
    error_message = "The extension library policy must not be attached when enable_script_runner is false."
  }
}

run "aws_managed_policy_arn_is_accepted" {
  command = plan

  variables {
    ecs_task_role_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
  }

  assert {
    condition     = aws_iam_role_policy_attachment.ecs_task_role_policy_supplied[0].policy_arn == "arn:aws:iam::aws:policy/ReadOnlyAccess"
    error_message = "An AWS managed policy ARN must be accepted."
  }
}

run "invalid_policy_arns_fail" {
  command = plan

  variables {
    ecs_task_role_policy_arn                   = "not-an-arn"
    ecs_task_execution_role_policy_arn         = "arn:aws:iam::123456789012:role/x"
    ecs_task_execution_role_keypair_policy_arn = "not-an-arn"
    script_runner_extension_library_policy_arn = "not-an-arn"
  }

  expect_failures = [
    var.ecs_task_role_policy_arn,
    var.ecs_task_execution_role_policy_arn,
    var.ecs_task_execution_role_keypair_policy_arn,
    var.script_runner_extension_library_policy_arn,
  ]
}
